from datetime import UTC, datetime
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

import app.api.routes.devices as devices_routes
from app.api.dependencies.auth import get_current_identity
from app.domain.device import Device, DevicePlatform
from app.domain.user import User
from app.main import app


client = TestClient(app)


class FakeUserRepository:
    def __init__(self, user):
        self.user = user

    def get_by_firebase_uid(self, firebase_uid):
        return self.user


class FakeDeviceRepository:
    def __init__(
        self,
        device=None,
        stale=False,
    ):
        self.device = device
        self.stale = stale
        self.saved_position = None

    def get_active_by_user_and_installation(
        self,
        user_id,
        installation_id,
    ):
        if self.device is None:
            return None

        if (
            self.device.user_id == user_id
            and self.device.installation_id == installation_id
            and self.device.is_active
        ):
            return self.device

        return None

    def save_position(self, position):
        if self.stale:
            return None

        self.saved_position = position
        return position


def create_user():
    return User(
        firebase_uid="firebase-jonathan",
        username="jonathan",
        email="jonathan@example.com",
    )


def create_device(user):
    return Device(
        user_id=user.id,
        installation_id=uuid4(),
        platform=DevicePlatform.ANDROID,
    )


@pytest.fixture(autouse=True)
def authenticated_user():
    app.dependency_overrides[get_current_identity] = lambda: {
        "uid": "firebase-jonathan",
    }

    yield

    app.dependency_overrides.clear()


def configure_repositories(
    monkeypatch,
    user,
    device=None,
    stale=False,
):
    device_repository = FakeDeviceRepository(
        device=device,
        stale=stale,
    )

    monkeypatch.setattr(
        devices_routes,
        "repositories",
        lambda: (
            FakeUserRepository(user),
            device_repository,
        ),
    )

    return device_repository


def valid_payload():
    return {
        "position": {
            "type": "Point",
            "coordinates": [
                5.37,
                43.29,
            ],
        },
        "accuracy_m": 18.0,
        "heading_deg": 90.0,
        "measured_at": "2026-10-02T08:15:00Z",
    }


def test_record_position_returns_200(
    monkeypatch,
):
    user = create_user()
    device = create_device(user)

    repository = configure_repositories(
        monkeypatch,
        user,
        device,
    )

    response = client.put(
        "/api/v1/devices/current/position",
        headers={
            "X-Installation-ID": str(
                device.installation_id
            ),
        },
        json=valid_payload(),
    )

    assert response.status_code == 200

    body = response.json()

    assert body["position"] == {
        "type": "Point",
        "coordinates": [
            5.37,
            43.29,
        ],
    }

    assert body["accuracy_m"] == 18.0
    assert body["heading_deg"] == 90.0
    assert repository.saved_position is not None
    assert (
        repository.saved_position.device_id
        == device.id
    )


def test_position_requires_installation_header(
    monkeypatch,
):
    user = create_user()
    device = create_device(user)

    configure_repositories(
        monkeypatch,
        user,
        device,
    )

    response = client.put(
        "/api/v1/devices/current/position",
        json=valid_payload(),
    )

    assert response.status_code == 422
    assert (
        response.json()["error"]["code"]
        == "request_validation_error"
    )


def test_position_rejects_invalid_installation_uuid(
    monkeypatch,
):
    user = create_user()
    device = create_device(user)

    configure_repositories(
        monkeypatch,
        user,
        device,
    )

    response = client.put(
        "/api/v1/devices/current/position",
        headers={
            "X-Installation-ID": "not-a-uuid",
        },
        json=valid_payload(),
    )

    assert response.status_code == 422
    assert (
        response.json()["error"]["code"]
        == "request_validation_error"
    )


def test_position_returns_404_for_unknown_device(
    monkeypatch,
):
    user = create_user()

    configure_repositories(
        monkeypatch,
        user,
        device=None,
    )

    response = client.put(
        "/api/v1/devices/current/position",
        headers={
            "X-Installation-ID": str(
                uuid4()
            ),
        },
        json=valid_payload(),
    )

    assert response.status_code == 404
    assert (
        response.json()["error"]["code"]
        == "device_not_found"
    )


def test_position_rejects_accuracy_above_50m(
    monkeypatch,
):
    user = create_user()
    device = create_device(user)

    configure_repositories(
        monkeypatch,
        user,
        device,
    )

    payload = valid_payload()
    payload["accuracy_m"] = 75.0

    response = client.put(
        "/api/v1/devices/current/position",
        headers={
            "X-Installation-ID": str(
                device.installation_id
            ),
        },
        json=payload,
    )

    assert response.status_code == 422
    assert (
        response.json()["error"]["code"]
        == "gps_precision_insufficient"
    )


def test_position_rejects_stale_measurement(
    monkeypatch,
):
    user = create_user()
    device = create_device(user)

    configure_repositories(
        monkeypatch,
        user,
        device,
        stale=True,
    )

    response = client.put(
        "/api/v1/devices/current/position",
        headers={
            "X-Installation-ID": str(
                device.installation_id
            ),
        },
        json=valid_payload(),
    )

    assert response.status_code == 409
    assert (
        response.json()["error"]["code"]
        == "device_position_stale"
    )
