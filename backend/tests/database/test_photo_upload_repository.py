from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, datetime, timedelta
from hashlib import sha256
from threading import Event
from uuid import uuid4

from fastapi.testclient import TestClient
import psycopg
from psycopg import sql
from psycopg.conninfo import make_conninfo
import pytest

from app.api.dependencies.auth import get_current_identity
from app.application.services.clean_unused_photos import CleanUnusedPhotos
from app.application.services.upload_report_photo import UploadReportPhoto
from app.domain.errors import PhotoAlreadyUploadedError, PhotoStorageError
from app.domain.report_photo import UploadStatus
from app.infrastructure.adapters.jpeg_validator import JpegValidator
from app.infrastructure.database.runtime_permissions import (
    grant_runtime_table_permissions,
)
from app.infrastructure.repositories.postgresql_photo_repository import (
    PostgreSQLPhotoRepository,
)
from app.infrastructure.repositories.postgresql_user_repository import (
    PostgreSQLUserRepository,
)
from app.main import app
from tests.photo_helpers import FakePhotoStorage, jpeg_bytes


@pytest.fixture
def photo_setup(db, dsn, monkeypatch):
    connection, ids = db
    monkeypatch.setenv("DATABASE_URL", dsn)
    uid = connection.execute(
        "SELECT firebase_uid FROM nowave.users WHERE id = %s", (ids["user"],)
    ).fetchone()[0]
    connection.commit()
    repository = PostgreSQLPhotoRepository()
    storage = FakePhotoStorage()
    service = UploadReportPhoto(
        PostgreSQLUserRepository(), repository, JpegValidator(), storage
    )
    return service, uid, ids["report"], repository, storage


def send(setup, content=None):
    service, uid, report_id, _, _ = setup
    return service.execute(uid, report_id, content or jpeg_bytes(), "image/jpeg")


def test_upload_retry_uses_existing_row_and_preserves_report(db, photo_setup):
    connection, ids = db
    before = connection.execute(
        "SELECT status, version, expires_at FROM nowave.reports WHERE id = %s",
        (ids["report"],),
    ).fetchone()
    first, second = send(photo_setup), send(photo_setup)
    assert first.created and not second.created
    assert (
        connection.execute(
            "SELECT count(*) FROM nowave.report_photos WHERE report_id = %s",
            (ids["report"],),
        ).fetchone()[0]
        == 1
    )
    assert (
        connection.execute(
            "SELECT status, version, expires_at FROM nowave.reports WHERE id = %s",
            (ids["report"],),
        ).fetchone()
        == before
    )
    assert len(photo_setup[4].objects) == 1


def test_manual_report_has_no_photo_session(db, photo_setup):
    with photo_setup[3].lock_for_upload(db[1]["manual"]) as session:
        assert session.photo is None


def test_storage_failure_commits_failed_and_retry_succeeds(photo_setup):
    storage = photo_setup[4]
    storage.fail_store = True
    with pytest.raises(PhotoStorageError):
        send(photo_setup)
    with photo_setup[3].lock_for_upload(photo_setup[2]) as session:
        assert session.photo.status == UploadStatus.FAILED
    storage.fail_store = False
    assert send(photo_setup).created


@pytest.mark.parametrize("different", [False, True])
def test_concurrent_requests_finalize_once(photo_setup, different):
    storage = photo_setup[4]
    entered, release = Event(), Event()
    original_store = storage.store

    def slow_store(*args):
        original_store(*args)
        entered.set()
        assert release.wait(2)

    storage.store = slow_store
    with ThreadPoolExecutor(max_workers=2) as pool:
        first = pool.submit(send, photo_setup)
        try:
            assert entered.wait(2)
            second = pool.submit(
                send, photo_setup, jpeg_bytes("red") if different else None
            )
        finally:
            release.set()
        assert first.result(timeout=5).created
        if different:
            with pytest.raises(PhotoAlreadyUploadedError):
                second.result(timeout=5)
        else:
            assert not second.result(timeout=5).created
    assert storage.store_calls == 1
    assert len(storage.objects) == 1


def test_lost_storage_response_followed_by_concurrent_retry_keeps_photo(photo_setup):
    storage = photo_setup[4]
    entered, release = Event(), Event()
    original_store = storage.store

    def first_response_lost(*args):
        original_store(*args)
        if storage.store_calls == 1:
            entered.set()
            assert release.wait(2)
            raise PhotoStorageError("lost response")

    storage.store = first_response_lost
    with ThreadPoolExecutor(max_workers=2) as pool:
        first = pool.submit(send, photo_setup)
        try:
            assert entered.wait(2)
            second = pool.submit(send, photo_setup)
        finally:
            release.set()
        with pytest.raises(PhotoStorageError):
            first.result(timeout=5)
        assert second.result(timeout=5).created
    with photo_setup[3].lock_for_upload(photo_setup[2]) as session:
        assert session.photo.status == UploadStatus.UPLOADED
        assert session.photo.object_key in storage.objects


def test_cleanup_waits_for_upload_and_keeps_its_committed_object(photo_setup):
    _, _, _, repository, storage = photo_setup
    entered, release, scan_started = Event(), Event(), Event()
    original_store, original_list = storage.store, storage.list_photos

    def slow_store(key, content, mime):
        original_store(key, content, mime)
        storage.modified_at[key] = datetime.now(UTC) - timedelta(hours=2)
        entered.set()
        assert release.wait(2)

    def observed_list():
        scan_started.set()
        yield from original_list()

    storage.store, storage.list_photos = slow_store, observed_list
    with ThreadPoolExecutor(max_workers=2) as pool:
        upload = pool.submit(send, photo_setup)
        try:
            assert entered.wait(2)
            cleanup = pool.submit(CleanUnusedPhotos(repository, storage).execute)
            assert scan_started.wait(2)
        finally:
            release.set()
        assert upload.result(timeout=5).created
        assert cleanup.result(timeout=5) == 0
    assert len(storage.objects) == 1


def test_cleanup_removes_old_object_without_photo_row(photo_setup):
    _, _, _, repository, storage = photo_setup
    key = f"reports/{uuid4()}/{sha256(b'orphan').hexdigest()}/{uuid4().hex}.jpg"
    storage.store(key, b"orphan", "image/jpeg")
    assert (
        CleanUnusedPhotos(repository, storage).execute(
            datetime.now(UTC) + timedelta(hours=2)
        )
        == 1
    )
    assert not storage.objects


def test_upload_works_with_production_table_privileges(
    db, dsn, monkeypatch, photo_setup
):
    role_name = "nw112_runtime_" + uuid4().hex
    role = sql.Identifier(role_name)
    with psycopg.connect(dsn, autocommit=True) as admin:
        admin.execute(
            sql.SQL("CREATE ROLE {} NOSUPERUSER NOCREATEDB NOCREATEROLE").format(role)
        )
        try:
            grant_runtime_table_permissions(admin, role_name)
            monkeypatch.setenv(
                "DATABASE_URL", make_conninfo(dsn, options=f"-c role={role_name}")
            )
            assert send(photo_setup).created
            assert not send(photo_setup).created
            assert admin.execute(
                "SELECT has_table_privilege(%s, 'nowave.report_photos', 'UPDATE')",
                (role_name,),
            ).fetchone()[0]
            assert not admin.execute(
                "SELECT has_table_privilege(%s, 'nowave.report_photos', 'DELETE')",
                (role_name,),
            ).fetchone()[0]
        finally:
            admin.execute(sql.SQL("DROP OWNED BY {}").format(role))
            admin.execute(sql.SQL("DROP ROLE {}").format(role))


def test_api_upload_read_hide_and_retry_against_postgis(db, photo_setup, monkeypatch):
    _, uid, report_id, _, storage = photo_setup
    monkeypatch.setattr("app.api.routes.reports.get_photo_storage", lambda: storage)
    monkeypatch.setattr(
        "app.api.routes.report_details.get_photo_storage", lambda: storage
    )
    app.dependency_overrides[get_current_identity] = lambda: {"uid": uid}
    try:
        client = TestClient(app)
        path = f"/api/v1/reports/{report_id}"
        first = client.post(
            path + "/photo", files={"file": ("photo.jpg", jpeg_bytes(), "image/jpeg")}
        )
        assert first.status_code == 201
        assert first.json()["upload_status"] == "uploaded"
        assert (
            client.get(path).json()["photo"]["url"].startswith("https://signed.test/")
        )
        assert len(storage.signed) == 1
        connection = db[0]
        connection.execute(
            "UPDATE nowave.report_photos SET hidden_at = now() WHERE report_id = %s",
            (report_id,),
        )
        connection.commit()
        retry = client.post(
            path + "/photo", files={"file": ("photo.jpg", jpeg_bytes(), "image/jpeg")}
        )
        assert retry.status_code == 200
        assert "url" not in retry.json()
        assert client.get(path).json()["photo"]["url"] is None
        assert len(storage.signed) == 1
    finally:
        app.dependency_overrides.clear()
