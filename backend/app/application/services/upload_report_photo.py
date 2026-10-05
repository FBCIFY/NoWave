from dataclasses import dataclass
from hashlib import sha256
import logging
from uuid import UUID, uuid4

from app.application.ports.image_validator import ImageValidator
from app.application.ports.photo_repository import PhotoRepository
from app.application.ports.photo_storage import PhotoStoragePort
from app.application.ports.user_repository import UserRepository
from app.domain.errors import (
    InactiveUserError,
    PhotoAlreadyUploadedError,
    PhotoStorageError,
    PhotoUploadForbiddenError,
    ReportNotFoundError,
    UserNotFoundError,
)
from app.domain.report_photo import UploadStatus
from app.domain.user import UserStatus

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class UploadReportPhotoResult:
    report_id: UUID
    upload_status: UploadStatus
    size_bytes: int
    mime_type: str
    created: bool


class UploadReportPhoto:
    def __init__(
        self,
        user_repository: UserRepository,
        photo_repository: PhotoRepository,
        image_validator: ImageValidator,
        photo_storage: PhotoStoragePort,
    ):
        self.user_repository = user_repository
        self.photo_repository = photo_repository
        self.image_validator = image_validator
        self.photo_storage = photo_storage

    def execute(
        self,
        firebase_uid: str,
        report_id: UUID,
        content: bytes,
        declared_mime_type: str | None,
    ) -> UploadReportPhotoResult:
        user = self.user_repository.get_by_firebase_uid(firebase_uid)
        if user is None:
            raise UserNotFoundError("NoWave user not found")
        if user.status != UserStatus.ACTIVE:
            raise InactiveUserError("user is not active")

        storage_error = None
        with self.photo_repository.lock_for_upload(report_id) as session:
            photo = session.photo
            if photo is None:
                raise ReportNotFoundError("photo report not found")
            if photo.author_id != user.id:
                raise PhotoUploadForbiddenError(
                    "only the report owner can upload its photo"
                )

            image = self.image_validator.validate(content, declared_mime_type)
            digest = sha256(image.content).hexdigest()
            content_prefix = f"reports/{report_id}/{digest}/"
            created = photo.status != UploadStatus.UPLOADED

            if not created:
                # Recover a lost HTTP response without writing the object again.
                if (
                    not photo.object_key
                    or not photo.object_key.startswith(content_prefix)
                    or photo.size_bytes != image.size_bytes
                    or photo.mime_type != image.mime_type
                ):
                    raise PhotoAlreadyUploadedError("report photo is already uploaded")
            else:
                # Never reuse a failed attempt's key. Even a delayed DELETE after
                # a lost database connection cannot touch the next attempt's object.
                object_key = f"{content_prefix}{uuid4().hex}.jpg"
                try:
                    self.photo_storage.store(object_key, image.content, image.mime_type)
                except PhotoStorageError as exc:
                    session.mark_failed()
                    storage_error = exc
                else:
                    session.mark_uploaded(object_key, image.size_bytes, image.mime_type)

        # Commit 'failed' before returning the error. Never delete on an uncertain
        # storage/commit outcome: cleanup checks the committed row under the same lock.
        if storage_error is not None:
            logger.warning(
                "Photo upload failed; any unused object will be cleaned later"
            )
            raise storage_error

        return UploadReportPhotoResult(
            report_id=report_id,
            upload_status=UploadStatus.UPLOADED,
            size_bytes=image.size_bytes,
            mime_type=image.mime_type,
            created=created,
        )
