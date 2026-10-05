from concurrent.futures import ThreadPoolExecutor
from dataclasses import replace
from datetime import UTC, datetime, timedelta
from uuid import uuid4

import psycopg
import pytest

from app.application.services.clean_unused_photos import CleanUnusedPhotos
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
from tests.photo_helpers import build_service, jpeg_bytes, upload


def test_success_and_lost_http_response_reuse_one_photo_and_object():
    service, user, repository, storage = build_service()
    first = upload(service, user, repository.photo.report_id)
    second = upload(service, user, repository.photo.report_id)
    assert first.created and not second.created
    assert first.upload_status == UploadStatus.UPLOADED
    assert len(storage.objects) == storage.store_calls == 1
    assert not storage.signed  # Only GET may authorize a read URL.


def test_different_image_after_success_is_rejected():
    service, user, repository, storage = build_service()
    upload(service, user, repository.photo.report_id)
    with pytest.raises(PhotoAlreadyUploadedError):
        upload(service, user, repository.photo.report_id, jpeg_bytes("red"))
    assert storage.store_calls == 1


@pytest.mark.parametrize(
    "case,error",
    [
        ("owner", PhotoUploadForbiddenError),
        ("missing", ReportNotFoundError),
        ("user", UserNotFoundError),
        ("suspended", InactiveUserError),
    ],
)
def test_authorization_precedes_storage(case, error):
    service, user, repository, storage = build_service()
    report_id = repository.photo.report_id
    if case == "owner":
        repository.photo = replace(repository.photo, author_id=uuid4())
    elif case == "missing":
        report_id = uuid4()
    elif case == "user":
        service.user_repository.user = None
    else:
        user.status = UserStatus.SUSPENDED
    with pytest.raises(error):
        upload(service, user, report_id)
    assert not storage.objects


def test_storage_failure_preserves_object_until_safe_cleanup_and_allows_retry():
    service, user, repository, storage = build_service()
    storage.fail_store = True
    with pytest.raises(PhotoStorageError):
        upload(service, user, repository.photo.report_id)
    assert repository.photo.status == UploadStatus.FAILED
    assert len(storage.objects) == 1
    storage.fail_store = False
    old_key = next(iter(storage.objects))
    assert upload(service, user, repository.photo.report_id).created
    assert repository.photo.object_key != old_key
    assert len(storage.objects) == 2
    cleanup = CleanUnusedPhotos(repository, storage)
    assert cleanup.execute(datetime.now(UTC) + timedelta(hours=2)) == 1
    assert repository.photo.object_key in storage.objects


@pytest.mark.parametrize(
    "failure,expected_created", [("before", True), ("after", False)]
)
def test_retry_resolves_uncertain_database_commit(failure, expected_created):
    service, user, repository, storage = build_service()
    repository.commit_failure = failure
    with pytest.raises(psycopg.OperationalError):
        upload(service, user, repository.photo.report_id)
    assert len(storage.objects) == 1
    repository.commit_failure = None
    result = upload(service, user, repository.photo.report_id)
    assert result.created is expected_created
    assert repository.photo.object_key in storage.objects


def test_parallel_identical_uploads_keep_the_winning_object():
    service, user, repository, storage = build_service()
    with ThreadPoolExecutor(max_workers=2) as pool:
        futures = [
            pool.submit(upload, service, user, repository.photo.report_id)
            for _ in range(2)
        ]
        results = [future.result() for future in futures]
    assert sorted(result.created for result in results) == [False, True]
    assert storage.store_calls == 1
    assert repository.photo.object_key in storage.objects


def test_cleanup_keeps_referenced_and_recent_objects():
    service, user, repository, storage = build_service()
    upload(service, user, repository.photo.report_id)
    now = datetime.now(UTC)
    old_key = repository.photo.object_key
    storage.modified_at[old_key] = now - timedelta(hours=2)
    recent_key = f"reports/{repository.photo.report_id}/{'a' * 64}/{uuid4().hex}.jpg"
    storage.store(recent_key, b"recent", "image/jpeg")
    cleanup = CleanUnusedPhotos(repository, storage)
    assert cleanup.execute(now) == 0
    assert len(storage.objects) == 2


def test_cleanup_recovers_from_delete_failure_and_process_restart(caplog):
    service, user, repository, storage = build_service()
    storage.fail_store = True
    with pytest.raises(PhotoStorageError):
        upload(service, user, repository.photo.report_id)
    now = datetime.now(UTC) + timedelta(hours=2)
    storage.fail_delete = True
    assert CleanUnusedPhotos(repository, storage).execute(now) == 0
    assert storage.objects
    assert "next scan will retry" in caplog.text
    storage.fail_delete = False
    assert CleanUnusedPhotos(repository, storage).execute(now) == 1
    assert not storage.objects


def test_cleanup_ignores_other_bucket_contents():
    _, _, repository, storage = build_service()
    for key in ["unrelated/file.jpg", "reports/not-our-key.jpg"]:
        storage.store(key, b"private", "image/jpeg")
    assert (
        CleanUnusedPhotos(repository, storage).execute(
            datetime.now(UTC) + timedelta(hours=2)
        )
        == 0
    )
    assert len(storage.objects) == 2


def test_late_delete_after_timeout_cannot_remove_a_new_attempt():
    service, user, repository, storage = build_service()
    storage.fail_store = True
    with pytest.raises(PhotoStorageError):
        upload(service, user, repository.photo.report_id)

    delayed_deletes = []
    original_delete = storage.delete

    def delayed_delete(key):
        delayed_deletes.append(key)
        raise PhotoStorageError("response timed out; remote deletion is still running")

    storage.delete = delayed_delete
    CleanUnusedPhotos(repository, storage).execute(
        datetime.now(UTC) + timedelta(hours=2)
    )
    storage.fail_store = False
    assert upload(service, user, repository.photo.report_id).created

    for key in delayed_deletes:
        original_delete(key)
    assert repository.photo.object_key in storage.objects
    assert len(storage.objects) == 1
