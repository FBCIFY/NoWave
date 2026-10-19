from fastapi import Depends, FastAPI
from fastapi.testclient import TestClient

import app.api.dependencies.auth as auth_dependency
from app.api.errors.handlers import (
    email_not_verified_handler,
    inactive_user_handler,
    user_not_found_handler,
)
from app.domain.errors import (
    EmailNotVerifiedError,
    InactiveUserError,
    UserNotFoundError,
)
from app.domain.user import User, UserStatus


app = FastAPI()

app.add_exception_handler(
    EmailNotVerifiedError,
    email_not_verified_handler,
)
app.add_exception_handler(
    InactiveUserError,
    inactive_user_handler,
)
app.add_exception_handler(
    UserNotFoundError,
    user_not_found_handler,
)


@app.get("/authenticated")
def authenticated_route(
    identity: dict = Depends(
        auth_dependency.get_authenticated_identity
    ),
):
    return identity


@app.get("/active")
def active_route(
    identity: dict = Depends(
        auth_dependency.get_current_identity
    ),
):
    return identity


client = TestClient(app)


class FakeUserRepository:
    def __init__(self, user=None):
        self.user = user

    def get_by_firebase_uid(self, firebase_uid):
        if (
            self.user is not None
            and self.user.firebase_uid == firebase_uid
        ):
            return self.user

        return None


def make_user():
    return User(
        firebase_uid="firebase-user-123",
        username="Jonathan",
        email="user@nowave.test",
    )


def configure_auth(
    monkeypatch,
    *,
    identity,
    user=None,
):
    class FakeFirebaseAuthAdapter:
        def verify_token(self, token: str) -> dict:
            assert token == "valid-token"
            return identity

    monkeypatch.setattr(
        auth_dependency,
        "FirebaseAuthAdapter",
        FakeFirebaseAuthAdapter,
    )

    monkeypatch.setattr(
        auth_dependency,
        "PostgreSQLUserRepository",
        lambda: FakeUserRepository(user),
    )


def verified_identity():
    return {
        "uid": "firebase-user-123",
        "email": "user@nowave.test",
        "email_verified": True,
    }


def test_authenticated_identity_does_not_require_profile(
    monkeypatch,
):
    configure_auth(
        monkeypatch,
        identity=verified_identity(),
        user=None,
    )

    response = client.get(
        "/authenticated",
        headers={
            "Authorization": "Bearer valid-token",
        },
    )

    assert response.status_code == 200
    assert response.json()["uid"] == "firebase-user-123"


def test_active_user_returns_identity(monkeypatch):
    configure_auth(
        monkeypatch,
        identity=verified_identity(),
        user=make_user(),
    )

    response = client.get(
        "/active",
        headers={
            "Authorization": "Bearer valid-token",
        },
    )

    assert response.status_code == 200
    # The preloaded server profile must not become a JSON field or a claim.
    assert response.json() == verified_identity()


def test_missing_token_returns_401():
    response = client.get("/authenticated")

    assert response.status_code == 401
    assert response.json()["detail"] == "Authentication required"


def test_invalid_token_returns_401(monkeypatch):
    class FakeFirebaseAuthAdapter:
        def verify_token(self, token: str) -> dict:
            raise ValueError("invalid token")

    monkeypatch.setattr(
        auth_dependency,
        "FirebaseAuthAdapter",
        FakeFirebaseAuthAdapter,
    )

    response = client.get(
        "/authenticated",
        headers={
            "Authorization": "Bearer invalid-token",
        },
    )

    assert response.status_code == 401
    assert (
        response.json()["detail"]
        == "Invalid authentication token"
    )


def test_unverified_email_returns_403(monkeypatch):
    identity = verified_identity()
    identity["email_verified"] = False

    configure_auth(
        monkeypatch,
        identity=identity,
        user=make_user(),
    )

    response = client.get(
        "/active",
        headers={
            "Authorization": "Bearer valid-token",
        },
    )

    assert response.status_code == 403
    assert (
        response.json()["error"]["code"]
        == "email_not_verified"
    )


def test_missing_profile_returns_404(monkeypatch):
    configure_auth(
        monkeypatch,
        identity=verified_identity(),
        user=None,
    )

    response = client.get(
        "/active",
        headers={
            "Authorization": "Bearer valid-token",
        },
    )

    assert response.status_code == 404
    assert (
        response.json()["error"]["code"]
        == "user_not_found"
    )


def test_suspended_user_returns_403(monkeypatch):
    user = make_user()
    user.status = UserStatus.SUSPENDED

    configure_auth(
        monkeypatch,
        identity=verified_identity(),
        user=user,
    )

    response = client.get(
        "/active",
        headers={
            "Authorization": "Bearer valid-token",
        },
    )

    assert response.status_code == 403
    assert (
        response.json()["error"]["code"]
        == "user_inactive"
    )


def test_certificate_outage_returns_503_then_recovers(monkeypatch):
    from firebase_admin import auth

    outcomes = [auth.CertificateFetchError("private certificate URL", cause=OSError("network")), verified_identity()]

    class Adapter:
        def verify_token(self, token):
            outcome = outcomes.pop(0)
            if isinstance(outcome, Exception):
                raise outcome
            return outcome

    monkeypatch.setattr(auth_dependency, "FirebaseAuthAdapter", Adapter)
    headers = {"Authorization": "Bearer valid-token"}
    response = client.get("/authenticated", headers=headers)
    assert response.status_code == 503
    assert response.json() == {"detail": "Authentication service unavailable"}
    assert client.get("/authenticated", headers=headers).status_code == 200


import pytest
from firebase_admin import auth as firebase_auth
from firebase_admin.exceptions import UnavailableError
from google.auth.exceptions import TransportError
import requests


@pytest.mark.parametrize("error", [
    ValueError("bad token"),
    firebase_auth.InvalidIdTokenError("invalid signature"),
    firebase_auth.ExpiredIdTokenError("expired", cause=None),
    firebase_auth.RevokedIdTokenError("revoked"),
    firebase_auth.UserDisabledError("disabled"),
    firebase_auth.UserNotFoundError("deleted"),
])
def test_rejected_identities_remain_401(monkeypatch, error):
    class Adapter:
        def verify_token(self, token):
            raise error
    monkeypatch.setattr(auth_dependency, "FirebaseAuthAdapter", Adapter)
    response = client.get("/authenticated", headers={"Authorization": "Bearer private-token"})
    assert response.status_code == 401
    assert "private" not in response.text


@pytest.mark.parametrize("error", [
    UnavailableError("private details"), TransportError("private details"),
    requests.Timeout("private details"),
])
def test_transport_and_provider_outages_are_503(monkeypatch, error):
    class Adapter:
        def verify_token(self, token):
            raise error
    monkeypatch.setattr(auth_dependency, "FirebaseAuthAdapter", Adapter)
    response = client.get("/authenticated", headers={"Authorization": "Bearer private-token"})
    assert response.status_code == 503
    assert "private" not in response.text


def test_initialization_outage_is_503(monkeypatch):
    def fail():
        raise OSError("private credential path")
    monkeypatch.setattr(auth_dependency, "FirebaseAuthAdapter", fail)
    response = client.get("/authenticated", headers={"Authorization": "Bearer token"})
    assert response.status_code == 503
    assert "private" not in response.text


def test_unexpected_programming_error_is_not_a_401(monkeypatch):
    class Adapter:
        def verify_token(self, token):
            raise RuntimeError("bug")
    monkeypatch.setattr(auth_dependency, "FirebaseAuthAdapter", Adapter)
    with pytest.raises(RuntimeError, match="bug"):
        client.get("/authenticated", headers={"Authorization": "Bearer token"})


def test_public_error_envelope_has_stable_unavailable_code(monkeypatch):
    from app.main import app as api_app
    class Adapter:
        def verify_token(self, token):
            raise firebase_auth.CertificateFetchError("private URL", cause=None)
    monkeypatch.setattr(auth_dependency, "FirebaseAuthAdapter", Adapter)
    response = TestClient(api_app).get("/api/v1/users/me", headers={"Authorization": "Bearer token"})
    assert response.status_code == 503
    assert response.json()["error"]["code"] == "authentication_unavailable"
    assert "private" not in response.text
