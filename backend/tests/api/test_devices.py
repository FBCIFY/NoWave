from fastapi.testclient import TestClient

from app.api.dependencies.auth import get_current_identity
from app.domain.errors import DeviceConflictError
from app.domain.user import User
from app.main import app


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


class FakeDeviceRepository:
    def __init__(self, conflict=False):
        self.device = None
        self.conflict = conflict

    def register(self, device):
        if self.conflict:
            raise DeviceConflictError(
                "installation belongs to another user"
            )

        self.device = device
        return device


def verified_identity():
    return {
        "uid": "firebase-user-123",
        "email": "user@nowave.test",
        "email_verified": True,
    }


def make_user():
    return User(
        firebase_uid="firebase-user-123",
        username="Jonathan",
        email="user@nowave.test",
    )


def setup_repositories(
    monkeypatch,
    user_repository,
    device_repository,
):
    monkeypatch.setattr(
        "app.api.routes.devices.PostgreSQLUserRepository",
        lambda: user_repository,
    )

    monkeypatch.setattr(
        "app.api.routes.devices.PostgreSQLDeviceRepository",
        lambda: device_repository,
    )


def test_register_current_device(monkeypatch):
    user = make_user()

    device_repository = FakeDeviceRepository()

    setup_repositories(
        monkeypatch,
        FakeUserRepository(user),
        device_repository,
    )

    app.dependency_overrides[
        get_current_identity
    ] = verified_identity

    client = TestClient(app)

    response = client.put(
        "/api/v1/devices/current",
        json={
            "installation_id": (
                "9d3f6a2e-7237-4dab-9fe9-054b4670d425"
            ),
            "platform": "android",
            "fcm_token": "test-fcm-token",
        },
    )

    app.dependency_overrides.clear()

    assert response.status_code == 200

    data = response.json()

    assert (
        data["installation_id"]
        == "9d3f6a2e-7237-4dab-9fe9-054b4670d425"
    )
    assert data["platform"] == "android"
    assert data["is_active"] is True

    assert "fcm_token" not in data
    assert "user_id" not in data

    assert device_repository.device is not None
    assert device_repository.device.user_id == user.id


def test_register_device_rejects_invalid_platform(
    monkeypatch,
):
    setup_repositories(
        monkeypatch,
        FakeUserRepository(make_user()),
        FakeDeviceRepository(),
    )

    app.dependency_overrides[
        get_current_identity
    ] = verified_identity

    client = TestClient(app)

    response = client.put(
        "/api/v1/devices/current",
        json={
            "installation_id": (
                "9d3f6a2e-7237-4dab-9fe9-054b4670d425"
            ),
            "platform": "windows",
        },
    )

    app.dependency_overrides.clear()

    assert response.status_code == 422


def test_register_device_conflict_returns_409(
    monkeypatch,
):
    setup_repositories(
        monkeypatch,
        FakeUserRepository(make_user()),
        FakeDeviceRepository(conflict=True),
    )

    app.dependency_overrides[
        get_current_identity
    ] = verified_identity

    client = TestClient(app)

    response = client.put(
        "/api/v1/devices/current",
        json={
            "installation_id": (
                "9d3f6a2e-7237-4dab-9fe9-054b4670d425"
            ),
            "platform": "android",
        },
    )

    app.dependency_overrides.clear()

    assert response.status_code == 409
    assert (
        response.json()["error"]["code"]
        == "device_conflict"
    )


def test_device_route_requires_authentication():
    app.dependency_overrides.clear()

    client = TestClient(app)

    response = client.put(
        "/api/v1/devices/current",
        json={
            "installation_id": (
                "9d3f6a2e-7237-4dab-9fe9-054b4670d425"
            ),
            "platform": "android",
        },
    )

    assert response.status_code == 401
