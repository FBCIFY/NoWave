from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

import app.api.routes.devices as devices_routes
from app.api.dependencies.auth import get_current_identity
from app.domain.user import User
from app.main import app


client = TestClient(app)


class FakeUserRepository:
    def __init__(self, user):
        self.user = user

    def get_by_firebase_uid(self, firebase_uid):
        return self.user


class FakeDeviceRepository:
    def __init__(self, result=True):
        self.result = result
        self.installation_id = None
        self.user_id = None

    def deactivate(
        self,
        user_id,
        installation_id,
    ):
        self.user_id = user_id
        self.installation_id = installation_id
        return self.result


def create_user():
    return User(
        firebase_uid="firebase-jonathan",
        username="jonathan",
        email="jonathan@example.com",
    )


@pytest.fixture(autouse=True)
def authenticated_user():
    app.dependency_overrides[
        get_current_identity
    ] = lambda: {
        "uid": "firebase-jonathan",
    }

    yield

    app.dependency_overrides.clear()


def test_delete_current_device_returns_204(
    monkeypatch,
):
    user = create_user()
    repository = FakeDeviceRepository()

    monkeypatch.setattr(
        devices_routes,
        "repositories",
        lambda: (
            FakeUserRepository(user),
            repository,
        ),
    )

    installation_id = uuid4()

    response = client.delete(
        "/api/v1/devices/current",
        headers={
            "X-Installation-ID": str(
                installation_id
            ),
        },
    )

    assert response.status_code == 204
    assert response.content == b""

    assert (
        repository.installation_id
        == installation_id
    )

    assert repository.user_id == user.id


def test_delete_requires_installation_header(
    monkeypatch,
):
    user = create_user()

    monkeypatch.setattr(
        devices_routes,
        "repositories",
        lambda: (
            FakeUserRepository(user),
            FakeDeviceRepository(),
        ),
    )

    response = client.delete(
        "/api/v1/devices/current"
    )

    assert response.status_code == 422
    assert (
        response.json()["error"]["code"]
        == "request_validation_error"
    )


def test_delete_unknown_device_returns_404(
    monkeypatch,
):
    user = create_user()

    monkeypatch.setattr(
        devices_routes,
        "repositories",
        lambda: (
            FakeUserRepository(user),
            FakeDeviceRepository(
                result=False,
            ),
        ),
    )

    response = client.delete(
        "/api/v1/devices/current",
        headers={
            "X-Installation-ID": str(
                uuid4()
            ),
        },
    )

    assert response.status_code == 404
    assert (
        response.json()["error"]["code"]
        == "device_not_found"
    )
