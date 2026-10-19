"""Use the real authentication dependency and an isolated in-memory profile store."""

import firebase_admin
from firebase_admin import auth
from fastapi.testclient import TestClient
import pytest

from app.main import app
from backend.tests.api.test_users import FakeUserRepository


@pytest.fixture
def setup(monkeypatch):
    repository = FakeUserRepository()
    monkeypatch.setattr(firebase_admin, "get_app", lambda: object())
    monkeypatch.setattr(
        "app.api.routes.users.PostgreSQLUserRepository", lambda: repository
    )
    app.dependency_overrides.clear()
    yield TestClient(app), repository
    app.dependency_overrides.clear()


def test_old_token_cannot_recreate_deleted_profile(monkeypatch, setup):
    client, repository = setup
    deleted = False

    def verify(token, check_revoked=False):
        assert token == "old-token"
        if deleted and check_revoked:
            raise auth.UserNotFoundError("deleted identity")
        return {
            "uid": "firebase-user-123",
            "email": "user@nowave.test",
            "email_verified": True,
        }

    def delete(uid):
        nonlocal deleted
        deleted = True

    monkeypatch.setattr(auth, "verify_id_token", verify)
    monkeypatch.setattr(auth, "delete_user", delete)
    headers = {"Authorization": "Bearer old-token"}
    assert (
        client.post(
            "/api/v1/users/me", json={"username": "Sailor"}, headers=headers
        ).status_code
        == 201
    )
    assert client.delete("/api/v1/users/me", headers=headers).status_code == 204
    response = client.post(
        "/api/v1/users/me", json={"username": "Sailor"}, headers=headers
    )
    assert response.status_code == 401
    assert repository.users == []
    # Deletion remains resumable with the same old token after lost 204.
    assert client.delete("/api/v1/users/me", headers=headers).status_code == 204


@pytest.mark.parametrize(
    "error",
    [
        auth.RevokedIdTokenError("revoked"),
        auth.UserDisabledError("disabled"),
        auth.UserNotFoundError("deleted"),
    ],
)
def test_registration_rejects_unavailable_identity(monkeypatch, setup, error):
    client, repository = setup

    def verify(token, check_revoked=False):
        assert check_revoked is True
        raise error

    monkeypatch.setattr(auth, "verify_id_token", verify)
    response = client.post(
        "/api/v1/users/me",
        json={"username": "Sailor"},
        headers={"Authorization": "Bearer token"},
    )
    assert response.status_code == 401
    assert repository.users == []


def test_registration_outage_is_retryable_without_creating_profile(monkeypatch, setup):
    from firebase_admin.exceptions import UnavailableError

    client, repository = setup
    calls = []

    def verify(token, check_revoked=False):
        assert check_revoked is True
        calls.append(token)
        if len(calls) == 1:
            raise UnavailableError("private backend error")
        return {"uid": "new-user", "email": "new@nowave.test", "email_verified": True}

    monkeypatch.setattr(auth, "verify_id_token", verify)
    headers = {"Authorization": "Bearer token"}
    response = client.post(
        "/api/v1/users/me", json={"username": "Sailor"}, headers=headers
    )
    assert response.status_code == 503
    assert repository.users == []
    assert (
        client.post(
            "/api/v1/users/me", json={"username": "Sailor"}, headers=headers
        ).status_code
        == 201
    )
    assert len(repository.users) == 1


def test_profile_read_keeps_standard_verification(monkeypatch, setup):
    client, _ = setup
    calls = []

    def verify(token, check_revoked=False):
        calls.append(check_revoked)
        return {"uid": "missing-user"}

    monkeypatch.setattr(auth, "verify_id_token", verify)
    assert (
        client.get(
            "/api/v1/users/me", headers={"Authorization": "Bearer token"}
        ).status_code
        == 404
    )
    assert calls == [False]
