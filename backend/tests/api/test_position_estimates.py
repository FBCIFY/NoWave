from fastapi.testclient import TestClient
import pytest

from app.api.dependencies.auth import (
    get_current_identity,
)
from app.domain.user import (
    User,
    UserStatus,
)
from app.main import app


class FakeUserRepository:
    def __init__(
        self,
        user=None,
    ):
        self.user = user

    def get_by_firebase_uid(
        self,
        firebase_uid,
    ):
        if self.user is None:
            return None

        if (
            self.user.firebase_uid
            != firebase_uid
        ):
            return None

        return self.user


def verified_identity():
    return {
        "uid": "firebase-user-123",
        "email": "user@nowave.test",
        "email_verified": True,
    }


def active_user():
    return User(
        firebase_uid="firebase-user-123",
        username="Jonathan",
        email="user@nowave.test",
    )


def build_payload(
    **changes,
):
    payload = {
        "observer_position": {
            "type": "Point",
            "coordinates": [
                5.3779,
                43.2945,
            ],
        },
        "gps_accuracy_m": 12.0,
        "azimuth_deg": 0.0,
        "inclination_deg": -30.0,
        "camera_height_m": 2.0,
        "camera_height_source": (
            "device_estimate"
        ),
        "camera_height_uncertainty_m": 0.1,
        "focal_length_mm": 24.0,
        "zoom_ratio": 1.0,
        "captured_at": (
            "2026-09-28T10:00:00Z"
        ),
    }

    payload.update(changes)

    return payload


def setup_user_repository(
    monkeypatch,
    user=None,
):
    monkeypatch.setattr(
        (
            "app.api.routes."
            "position_estimates."
            "PostgreSQLUserRepository"
        ),
        lambda: FakeUserRepository(
            user=user
        ),
    )


def test_position_estimate_returns_known_reference(
    monkeypatch,
):
    setup_user_repository(
        monkeypatch,
        user=active_user(),
    )

    app.dependency_overrides[
        get_current_identity
    ] = verified_identity

    try:
        client = TestClient(app)

        response = client.post(
            "/api/v1/position-estimates",
            json=build_payload(),
        )

    finally:
        app.dependency_overrides.clear()

    assert response.status_code == 200

    data = response.json()

    assert data[
        "estimated_distance_m"
    ] == pytest.approx(
        4.0,
        abs=0.01,
    )

    assert (
        data["estimated_position"]["type"]
        == "Point"
    )

    longitude, latitude = (
        data["estimated_position"]["coordinates"]
    )

    assert longitude == pytest.approx(
        5.3779,
        abs=0.000001,
    )

    assert latitude > 43.2945


def test_horizon_returns_unavailable(
    monkeypatch,
):
    setup_user_repository(
        monkeypatch,
        user=active_user(),
    )

    app.dependency_overrides[
        get_current_identity
    ] = verified_identity

    try:
        client = TestClient(app)

        response = client.post(
            "/api/v1/position-estimates",
            json=build_payload(
                inclination_deg=0.0,
            ),
        )

    finally:
        app.dependency_overrides.clear()

    assert response.status_code == 200

    assert response.json() == {
        "estimated_position": None,
        "estimated_distance_m": None,
    }


def test_accuracy_above_50_returns_documented_error(
    monkeypatch,
):
    setup_user_repository(
        monkeypatch,
        user=active_user(),
    )

    app.dependency_overrides[
        get_current_identity
    ] = verified_identity

    try:
        client = TestClient(app)

        response = client.post(
            "/api/v1/position-estimates",
            json=build_payload(
                gps_accuracy_m=50.1,
            ),
        )

    finally:
        app.dependency_overrides.clear()

    assert response.status_code == 422

    data = response.json()

    assert (
        data["error"]["code"]
        == "gps_precision_insufficient"
    )

    assert data["error"]["details"] == {
        "accuracy_m": 50.1,
        "maximum_accuracy_m": 50,
    }


def test_invalid_azimuth_returns_422(
    monkeypatch,
):
    setup_user_repository(
        monkeypatch,
        user=active_user(),
    )

    app.dependency_overrides[
        get_current_identity
    ] = verified_identity

    try:
        client = TestClient(app)

        response = client.post(
            "/api/v1/position-estimates",
            json=build_payload(
                azimuth_deg=360.0,
            ),
        )

    finally:
        app.dependency_overrides.clear()

    assert response.status_code == 422


def test_unknown_field_returns_422(
    monkeypatch,
):
    setup_user_repository(
        monkeypatch,
        user=active_user(),
    )

    app.dependency_overrides[
        get_current_identity
    ] = verified_identity

    payload = build_payload()
    payload["unexpected"] = True

    try:
        client = TestClient(app)

        response = client.post(
            "/api/v1/position-estimates",
            json=payload,
        )

    finally:
        app.dependency_overrides.clear()

    assert response.status_code == 422


def test_missing_authentication_returns_401():
    app.dependency_overrides.clear()

    client = TestClient(app)

    response = client.post(
        "/api/v1/position-estimates",
        json=build_payload(),
    )

    assert response.status_code == 401


def test_unknown_user_returns_404(
    monkeypatch,
):
    setup_user_repository(
        monkeypatch,
        user=None,
    )

    app.dependency_overrides[
        get_current_identity
    ] = verified_identity

    try:
        client = TestClient(app)

        response = client.post(
            "/api/v1/position-estimates",
            json=build_payload(),
        )

    finally:
        app.dependency_overrides.clear()

    assert response.status_code == 404

    assert (
        response.json()["error"]["code"]
        == "USER_NOT_FOUND"
    )


def test_suspended_user_returns_403(
    monkeypatch,
):
    user = active_user()
    user.status = UserStatus.SUSPENDED

    setup_user_repository(
        monkeypatch,
        user=user,
    )

    app.dependency_overrides[
        get_current_identity
    ] = verified_identity

    try:
        client = TestClient(app)

        response = client.post(
            "/api/v1/position-estimates",
            json=build_payload(),
        )

    finally:
        app.dependency_overrides.clear()

    assert response.status_code == 403

    assert (
        response.json()["error"]["code"]
        == "USER_INACTIVE"
    )


def test_extremely_large_camera_height_returns_422(
    monkeypatch,
):
    setup_user_repository(
        monkeypatch,
        user=active_user(),
    )

    app.dependency_overrides[
        get_current_identity
    ] = verified_identity

    try:
        client = TestClient(app)

        response = client.post(
            "/api/v1/position-estimates",
            json=build_payload(
                camera_height_m=1e100,
            ),
        )

    finally:
        app.dependency_overrides.clear()

    assert response.status_code == 422
