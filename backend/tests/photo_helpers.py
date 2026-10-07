"""Real JPEG fixtures and small, transactional doubles for photo tests."""

from contextlib import contextmanager
from dataclasses import replace
from datetime import UTC, datetime
from io import BytesIO
from threading import Lock
from uuid import uuid4

from PIL import Image
import psycopg

from app.application.ports.photo_repository import PhotoUploadData
from app.application.ports.photo_storage import StoredPhoto
from app.application.services.upload_report_photo import UploadReportPhoto
from app.domain.errors import PhotoStorageError
from app.domain.report_photo import UploadStatus
from app.domain.user import User
from app.infrastructure.adapters.jpeg_validator import JpegValidator


def jpeg_bytes(
    color="blue",
    *,
    exif=False,
    size=None,
    dimensions=(8, 8),
):
    output = BytesIO()
    metadata = Image.Exif()
    if exif:
        metadata[0x010F] = "Private camera metadata"
    options = {"exif": metadata} if exif else {}
    Image.new("RGB", dimensions, color).save(
        output,
        "JPEG",
        **options,
    )
    content = output.getvalue()
    if size is not None:
        padding = bytearray()
        remaining = size - len(content)
        while remaining:
            length = min(60_000, remaining)
            # Legal JPEG comment segments, rather than padding that is not decodable.
            padding.extend(
                b"\xff\xfe" + (length - 2).to_bytes(2, "big") + b"x" * (length - 4)
            )
            remaining -= length
        content = content[:2] + padding + content[2:]
    return bytes(content)


def jpeg_with_claimed_dimensions(
    width: int,
    height: int,
) -> bytes:
    """Change only the JPEG SOF dimensions without allocating the raster."""

    content = bytearray(jpeg_bytes())

    marker = content.find(b"\xff\xc0")

    if marker < 0:
        raise AssertionError(
            "baseline JPEG fixture has no SOF0 marker"
        )

    content[marker + 5 : marker + 7] = height.to_bytes(
        2,
        "big",
    )
    content[marker + 7 : marker + 9] = width.to_bytes(
        2,
        "big",
    )

    return bytes(content)


class FakeUserRepository:
    def __init__(self, user):
        self.user = user

    def get_by_firebase_uid(self, firebase_uid):
        return (
            self.user if self.user and self.user.firebase_uid == firebase_uid else None
        )


class FakePhotoSession:
    def __init__(self, photo):
        self.photo = photo

    def mark_uploaded(self, object_key, size_bytes, mime_type):
        self.photo = replace(
            self.photo,
            status=UploadStatus.UPLOADED,
            object_key=object_key,
            size_bytes=size_bytes,
            mime_type=mime_type,
        )

    def mark_failed(self):
        self.photo = replace(self.photo, status=UploadStatus.FAILED)


class FakePhotoRepository:
    def __init__(self, photo):
        self.photo = photo
        self.lock = Lock()
        self.commit_failure = None

    @contextmanager
    def lock_for_upload(self, report_id):
        with self.lock:
            photo = (
                self.photo if self.photo and self.photo.report_id == report_id else None
            )
            session = FakePhotoSession(photo)
            yield session
            if self.commit_failure == "before":
                raise psycopg.OperationalError("connection lost before commit")
            if photo is not None:
                self.photo = session.photo
            if self.commit_failure == "after":
                raise psycopg.OperationalError("commit response lost")


class FakePhotoStorage:
    def __init__(self):
        self.objects = {}
        self.modified_at = {}
        self.store_calls = 0
        self.signed = []
        self.fail_store = False
        self.fail_delete = False

    def store(self, object_key, content, mime_type):
        self.store_calls += 1
        self.objects[object_key] = content
        self.modified_at[object_key] = datetime.now(UTC)
        if self.fail_store:
            raise PhotoStorageError("storage response lost")

    def delete(self, object_key):
        if self.fail_delete:
            raise PhotoStorageError("delete unavailable")
        self.objects.pop(object_key, None)
        self.modified_at.pop(object_key, None)

    def create_read_url(self, object_key, expires_in):
        self.signed.append((object_key, expires_in))
        return f"https://signed.test/{object_key}"

    def list_photos(self):
        for key in list(self.objects):
            yield StoredPhoto(key, self.modified_at[key])


def build_service():
    user = User(
        firebase_uid="firebase-owner", username="owner", email="owner@nowave.test"
    )
    photo = PhotoUploadData(
        report_id=uuid4(),
        author_id=user.id,
        status=UploadStatus.PENDING,
        object_key=None,
        size_bytes=None,
        mime_type=None,
    )
    repository = FakePhotoRepository(photo)
    storage = FakePhotoStorage()
    service = UploadReportPhoto(
        FakeUserRepository(user), repository, JpegValidator(), storage
    )
    return service, user, repository, storage


def upload(service, user, report_id, content=None):
    return service.execute(
        user.firebase_uid, report_id, content or jpeg_bytes(), "image/jpeg"
    )
