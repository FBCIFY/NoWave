import asyncio
from dataclasses import replace
import time
from uuid import uuid4

from fastapi.testclient import TestClient
import httpx
import psycopg
import pytest

from app.api.dependencies.auth import get_current_identity
from app.main import app
from tests.photo_helpers import build_service, jpeg_bytes


@pytest.fixture
def setup_upload(monkeypatch):
    service, user, repository, storage = build_service()
    monkeypatch.setattr(
        "app.api.routes.reports.PostgreSQLUserRepository",
        lambda: service.user_repository,
    )
    monkeypatch.setattr(
        "app.api.routes.reports.PostgreSQLPhotoRepository", lambda: repository
    )
    monkeypatch.setattr("app.api.routes.reports.get_photo_storage", lambda: storage)
    app.dependency_overrides[get_current_identity] = lambda: {"uid": user.firebase_uid}
    yield user, repository, storage
    app.dependency_overrides.clear()


def post_photo(client, report_id, content=None, mime="image/jpeg"):
    return client.post(
        f"/api/v1/reports/{report_id}/photo",
        files={
            "file": ("photo.jpg", jpeg_bytes() if content is None else content, mime)
        },
    )


@pytest.mark.parametrize("size", [None, 500_000])
def test_owner_upload_returns_documented_metadata_and_identical_retry(
    setup_upload, size
):
    _, repository, storage = setup_upload
    content = jpeg_bytes(size=size)
    client = TestClient(app)
    first = post_photo(client, repository.photo.report_id, content)
    second = post_photo(client, repository.photo.report_id, content)
    assert first.status_code == 201
    assert second.status_code == 200
    assert (
        first.json()
        == second.json()
        == {
            "report_id": str(repository.photo.report_id),
            "upload_status": "uploaded",
            "size_bytes": len(content),
            "mime_type": "image/jpeg",
        }
    )
    assert len(storage.objects) == 1
    assert not storage.signed


def test_upload_requires_authentication(setup_upload):
    _, repository, storage = setup_upload
    app.dependency_overrides.clear()
    assert post_photo(TestClient(app), repository.photo.report_id).status_code == 401
    assert not storage.objects


def test_non_owner_returns_403(setup_upload):
    _, repository, storage = setup_upload
    repository.photo = replace(repository.photo, author_id=uuid4())
    response = post_photo(TestClient(app), repository.photo.report_id)
    assert response.status_code == 403
    assert response.json()["error"]["code"] == "photo_upload_forbidden"
    assert not storage.objects


@pytest.mark.parametrize(
    "content,mime",
    [
        (b"not-jpeg", "image/jpeg"),
        (b"", "image/jpeg"),
        (b"\xff\xd8\xfffake\xff\xd9", "image/jpeg"),
        (jpeg_bytes(exif=True), "image/jpeg"),
        (jpeg_bytes(size=500_001), "image/jpeg"),
        (jpeg_bytes(), "image/png"),
    ],
)
def test_invalid_images_return_422_without_storage(setup_upload, content, mime):
    _, repository, storage = setup_upload
    response = post_photo(TestClient(app), repository.photo.report_id, content, mime)
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "invalid_photo"
    assert not storage.objects


def test_raw_body_and_missing_file_are_rejected(setup_upload):
    _, repository, _ = setup_upload
    response = TestClient(app).post(
        f"/api/v1/reports/{repository.photo.report_id}/photo",
        content=jpeg_bytes(),
        headers={"Content-Type": "image/jpeg"},
    )
    assert response.status_code == 422


def test_large_chunked_body_is_rejected_before_multipart_parsing(setup_upload):
    _, repository, storage = setup_upload
    response = TestClient(app).post(
        f"/api/v1/reports/{repository.photo.report_id}/photo",
        content=iter([b"x" * 256_000] * 3),
        headers={"Content-Type": "multipart/form-data; boundary=test"},
    )
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "invalid_photo"
    assert not storage.objects


def test_unknown_or_manual_report_returns_404(setup_upload):
    assert post_photo(TestClient(app), uuid4()).status_code == 404


def test_different_photo_after_success_returns_409(setup_upload):
    _, repository, _ = setup_upload
    client = TestClient(app)
    assert post_photo(client, repository.photo.report_id).status_code == 201
    assert (
        post_photo(client, repository.photo.report_id, jpeg_bytes("red")).status_code
        == 409
    )


def test_storage_failure_returns_503_and_can_be_retried(setup_upload):
    _, repository, storage = setup_upload
    storage.fail_store = True
    client = TestClient(app)
    response = post_photo(client, repository.photo.report_id)
    assert response.status_code == 503
    assert response.json()["error"]["code"] == "photo_storage_unavailable"
    storage.fail_store = False
    assert post_photo(client, repository.photo.report_id).status_code == 201


def test_initial_database_outage_returns_safe_503(setup_upload, monkeypatch):
    _, repository, _ = setup_upload

    def unavailable(report_id):
        raise psycopg.OperationalError("private connection details")

    monkeypatch.setattr(repository, "lock_for_upload", unavailable)
    response = post_photo(TestClient(app), repository.photo.report_id)
    assert response.status_code == 503
    assert response.json()["error"]["code"] == "dependency_unavailable"
    assert "private" not in response.text


def test_openapi_describes_multipart_and_metadata():
    schema = app.openapi()
    operation = schema["paths"]["/api/v1/reports/{report_id}/photo"]["post"]
    assert "multipart/form-data" in operation["requestBody"]["content"]
    assert "200" in operation["responses"]
    assert (
        "upload_status"
        in schema["components"]["schemas"]["PhotoMetadataResponse"]["properties"]
    )


def test_slow_storage_does_not_block_event_loop(setup_upload):
    _, repository, storage = setup_upload
    original_store = storage.store

    def slow_store(*args):
        time.sleep(0.25)
        original_store(*args)

    storage.store = slow_store

    async def scenario():
        ticks = []
        running = True

        async def heartbeat():
            previous = time.monotonic()
            while running:
                await asyncio.sleep(0.005)
                now = time.monotonic()
                ticks.append(now - previous)
                previous = now

        pulse = asyncio.create_task(heartbeat())
        async with httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app), base_url="http://testserver"
        ) as client:
            response = await client.post(
                f"/api/v1/reports/{repository.photo.report_id}/photo",
                files={"file": ("photo.jpg", jpeg_bytes(), "image/jpeg")},
            )
        running = False
        await pulse
        assert response.status_code == 201
        assert max(ticks) < 0.15

    asyncio.run(scenario())
