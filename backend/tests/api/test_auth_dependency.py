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
    assert response.json()["uid"] == "firebase-user-123"


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
