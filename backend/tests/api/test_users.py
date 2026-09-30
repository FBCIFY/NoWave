from fastapi.testclient import TestClient

from app.api.dependencies.auth import get_current_identity
from app.domain.user import User
from app.main import app


class FakeUserRepository:
    def __init__(self, users=None):
        self.users = users or []

    def get_by_firebase_uid(self, firebase_uid):
        for user in self.users:
            if user.firebase_uid == firebase_uid:
                return user

        return None

    def get_by_username(self, username):
        for user in self.users:
            if user.username == username:
                return user

        return None

    def save(self, user):
        self.users.append(user)
        return user

    def update(self, user):
        return user

    def delete(self, user):
        self.users.remove(user)


def verified_identity():
    return {
        "uid": "firebase-user-123",
        "email": "user@nowave.test",
        "email_verified": True,
    }


def unverified_identity():
    return {
        "uid": "firebase-user-123",
        "email": "user@nowave.test",
        "email_verified": False,
    }


def test_create_my_profile(monkeypatch):
    repository = FakeUserRepository()

    monkeypatch.setattr(
        "app.api.routes.users.PostgreSQLUserRepository",
        lambda: repository,
    )

    app.dependency_overrides[get_current_identity] = verified_identity

    client = TestClient(app)

    response = client.post(
        "/api/v1/users/me",
        json={
            "username": "Jonathan",
        },
    )

    app.dependency_overrides.clear()

    assert response.status_code == 201

    data = response.json()

    assert data["username"] == "Jonathan"
    assert data["role"] == "user"
    assert data["status"] == "active"
    assert data["show_user_name"] is False
    assert data["show_boat_info"] is False
    assert data["notifications_enabled"] is False

    assert "firebase_uid" not in data
    assert "email" not in data


def test_create_profile_with_unverified_email_returns_403(monkeypatch):
    repository = FakeUserRepository()

    monkeypatch.setattr(
        "app.api.routes.users.PostgreSQLUserRepository",
        lambda: repository,
    )

    app.dependency_overrides[get_current_identity] = unverified_identity

    client = TestClient(app)

    response = client.post(
        "/api/v1/users/me",
        json={
            "username": "Jonathan",
        },
    )

    app.dependency_overrides.clear()

    assert response.status_code == 403
    assert response.json()["error"]["code"] == "EMAIL_NOT_VERIFIED"


def test_create_existing_profile_returns_409(monkeypatch):
    existing_user = User(
        firebase_uid="firebase-user-123",
        username="ExistingUser",
        email="existing@nowave.test",
    )

    repository = FakeUserRepository(
        users=[existing_user],
    )

    monkeypatch.setattr(
        "app.api.routes.users.PostgreSQLUserRepository",
        lambda: repository,
    )

    app.dependency_overrides[get_current_identity] = verified_identity

    client = TestClient(app)

    response = client.post(
        "/api/v1/users/me",
        json={
            "username": "Jonathan",
        },
    )

    app.dependency_overrides.clear()

    assert response.status_code == 409
    assert response.json()["error"]["code"] == "USER_ALREADY_EXISTS"


def test_create_profile_with_existing_username_returns_409(monkeypatch):
    existing_user = User(
        firebase_uid="another-firebase-user",
        username="Jonathan",
        email="another@nowave.test",
    )

    repository = FakeUserRepository(
        users=[existing_user],
    )

    monkeypatch.setattr(
        "app.api.routes.users.PostgreSQLUserRepository",
        lambda: repository,
    )

    app.dependency_overrides[get_current_identity] = verified_identity

    client = TestClient(app)

    response = client.post(
        "/api/v1/users/me",
        json={
            "username": "Jonathan",
        },
    )

    app.dependency_overrides.clear()

    assert response.status_code == 409
    assert response.json()["error"]["code"] == "USERNAME_ALREADY_EXISTS"


def test_create_profile_with_invalid_payload_returns_422(monkeypatch):
    repository = FakeUserRepository()

    monkeypatch.setattr(
        "app.api.routes.users.PostgreSQLUserRepository",
        lambda: repository,
    )

    app.dependency_overrides[get_current_identity] = verified_identity

    client = TestClient(app)

    response = client.post(
        "/api/v1/users/me",
        json={
            "username": "",
        },
    )

    app.dependency_overrides.clear()

    assert response.status_code == 422


def test_get_my_profile(monkeypatch):
    existing_user = User(
        firebase_uid="firebase-user-123",
        username="Jonathan",
        email="user@nowave.test",
    )

    repository = FakeUserRepository(
        users=[existing_user],
    )

    monkeypatch.setattr(
        "app.api.routes.users.PostgreSQLUserRepository",
        lambda: repository,
    )

    app.dependency_overrides[get_current_identity] = verified_identity

    client = TestClient(app)

    response = client.get(
        "/api/v1/users/me",
    )

    app.dependency_overrides.clear()

    assert response.status_code == 200

    data = response.json()

    assert data["username"] == "Jonathan"
    assert data["role"] == "user"
    assert data["status"] == "active"

    assert "firebase_uid" not in data
    assert "email" not in data


def test_get_missing_profile_returns_404(monkeypatch):
    repository = FakeUserRepository()

    monkeypatch.setattr(
        "app.api.routes.users.PostgreSQLUserRepository",
        lambda: repository,
    )

    app.dependency_overrides[get_current_identity] = verified_identity

    client = TestClient(app)

    response = client.get(
        "/api/v1/users/me",
    )

    app.dependency_overrides.clear()

    assert response.status_code == 404
    assert response.json()["error"]["code"] == "USER_NOT_FOUND"

    assert repository.users == []


def test_update_my_profile(monkeypatch):
    existing_user = User(
        firebase_uid="firebase-user-123",
        username="Jonathan",
        email="user@nowave.test",
    )

    repository = FakeUserRepository(
        users=[existing_user],
    )

    monkeypatch.setattr(
        "app.api.routes.users.PostgreSQLUserRepository",
        lambda: repository,
    )

    app.dependency_overrides[get_current_identity] = verified_identity

    client = TestClient(app)

    response = client.patch(
        "/api/v1/users/me",
        json={
            "username": "John",
            "nationality": "fr",
            "show_user_name": True,
        },
    )

    app.dependency_overrides.clear()

    assert response.status_code == 200

    data = response.json()

    assert data["username"] == "John"
    assert data["nationality"] == "FR"
    assert data["show_user_name"] is True

    assert "firebase_uid" not in data
    assert "email" not in data


def test_update_missing_profile_returns_404(monkeypatch):
    repository = FakeUserRepository()

    monkeypatch.setattr(
        "app.api.routes.users.PostgreSQLUserRepository",
        lambda: repository,
    )

    app.dependency_overrides[get_current_identity] = verified_identity

    client = TestClient(app)

    response = client.patch(
        "/api/v1/users/me",
        json={
            "username": "John",
        },
    )

    app.dependency_overrides.clear()

    assert response.status_code == 404
    assert response.json()["error"]["code"] == "USER_NOT_FOUND"


def test_update_with_existing_username_returns_409(monkeypatch):
    current_user = User(
        firebase_uid="firebase-user-123",
        username="Jonathan",
        email="user@nowave.test",
    )

    other_user = User(
        firebase_uid="another-firebase-user",
        username="Brice",
        email="brice@nowave.test",
    )

    repository = FakeUserRepository(
        users=[
            current_user,
            other_user,
        ],
    )

    monkeypatch.setattr(
        "app.api.routes.users.PostgreSQLUserRepository",
        lambda: repository,
    )

    app.dependency_overrides[get_current_identity] = verified_identity

    client = TestClient(app)

    response = client.patch(
        "/api/v1/users/me",
        json={
            "username": "Brice",
        },
    )

    app.dependency_overrides.clear()

    assert response.status_code == 409
    assert response.json()["error"]["code"] == "USERNAME_ALREADY_EXISTS"


def test_update_with_invalid_payload_returns_422(monkeypatch):
    existing_user = User(
        firebase_uid="firebase-user-123",
        username="Jonathan",
        email="user@nowave.test",
    )

    repository = FakeUserRepository(
        users=[existing_user],
    )

    monkeypatch.setattr(
        "app.api.routes.users.PostgreSQLUserRepository",
        lambda: repository,
    )

    app.dependency_overrides[get_current_identity] = verified_identity

    client = TestClient(app)

    response = client.patch(
        "/api/v1/users/me",
        json={
            "username": "",
        },
    )

    app.dependency_overrides.clear()

    assert response.status_code == 422


class FakeAuthProvider:
    def __init__(self):
        self.deleted_uids = []

    def delete_identity(self, firebase_uid):
        self.deleted_uids.append(firebase_uid)


def test_delete_my_profile(monkeypatch):
    existing_user = User(
        firebase_uid="firebase-user-123",
        username="Jonathan",
        email="user@nowave.test",
    )

    repository = FakeUserRepository(
        users=[existing_user],
    )

    auth_provider = FakeAuthProvider()

    monkeypatch.setattr(
        "app.api.routes.users.PostgreSQLUserRepository",
        lambda: repository,
    )

    monkeypatch.setattr(
        "app.api.routes.users.FirebaseAuthAdapter",
        lambda: auth_provider,
    )

    app.dependency_overrides[get_current_identity] = verified_identity

    client = TestClient(app)

    response = client.delete(
        "/api/v1/users/me",
    )

    app.dependency_overrides.clear()

    assert response.status_code == 204
    assert response.content == b""

    assert repository.users == []
    assert auth_provider.deleted_uids == [
        "firebase-user-123"
    ]


def test_delete_missing_profile_returns_404(monkeypatch):
    repository = FakeUserRepository()
    auth_provider = FakeAuthProvider()

    monkeypatch.setattr(
        "app.api.routes.users.PostgreSQLUserRepository",
        lambda: repository,
    )

    monkeypatch.setattr(
        "app.api.routes.users.FirebaseAuthAdapter",
        lambda: auth_provider,
    )

    app.dependency_overrides[get_current_identity] = verified_identity

    client = TestClient(app)

    response = client.delete(
        "/api/v1/users/me",
    )

    app.dependency_overrides.clear()

    assert response.status_code == 404
    assert response.json()["error"]["code"] == "USER_NOT_FOUND"

    assert repository.users == []
    assert auth_provider.deleted_uids == []
