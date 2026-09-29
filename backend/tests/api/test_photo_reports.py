from datetime import UTC, datetime, timedelta
from uuid import UUID

from fastapi.testclient import TestClient

from app.api.dependencies.auth import get_current_identity
from app.domain.report_photo import UploadStatus
from app.domain.report_positioning import StoredReportPositioning
from app.domain.user import User
from app.main import app


class FakeUserRepository:
    def __init__(self, user):
        self.user = user

    def get_by_firebase_uid(self, firebase_uid):
        if self.user.firebase_uid == firebase_uid:
            return self.user

        return None


class FakeReportRepository:
    def __init__(self):
        self.reports = []
        self.positioning = {}
        self.photo_status = {}

    def get_by_client_report_id(
        self,
        author_id,
        client_report_id,
    ):
        for report in self.reports:
            if (
                report.author_id == author_id
                and report.client_report_id == client_report_id
            ):
                return report

        return None

    def save(self, report):
        self.reports.append(report)
        return report

    def save_photo(
        self,
        report,
        measurements,
        estimate,
    ):
        self.reports.append(report)

        self.positioning[report.id] = StoredReportPositioning(
            report_id=report.id,
            measurements=measurements,
            estimated_longitude=estimate.longitude,
            estimated_latitude=estimate.latitude,
            estimated_distance_m=estimate.distance_m,
            algorithm_version=estimate.algorithm_version,
        )

        self.photo_status[report.id] = UploadStatus.PENDING

        return report

    def get_photo_positioning(
        self,
        report_id,
    ):
        return self.positioning.get(report_id)

    def get_photo_status(
        self,
        report_id,
    ):
        return self.photo_status.get(report_id)


def verified_identity():
    return {
        "uid": "firebase-photo-user",
        "email": "photo-user@nowave.test",
        "email_verified": True,
    }


def setup_repositories(monkeypatch):
    user = User(
        firebase_uid="firebase-photo-user",
        username="photo-user",
        email="photo-user@nowave.test",
    )

    repository = FakeReportRepository()

    monkeypatch.setattr(
        "app.api.routes.reports.PostgreSQLUserRepository",
        lambda: FakeUserRepository(user),
    )

    monkeypatch.setattr(
        "app.api.routes.reports.PostgreSQLReportRepository",
        lambda: repository,
    )

    return repository


def build_photo_payload(
    client_report_id,
    observed_at,
):
    return {
        "client_report_id": str(client_report_id),
        "category": "pollution",
        "positioning_mode": "photo",
        "description": "Pollution visible",
        "final_position": {
            "type": "Point",
            "coordinates": [
                5.40,
                43.31,
            ],
        },
        "observed_at": observed_at.isoformat(),
        "positioning": {
            "observer_position": {
                "type": "Point",
                "coordinates": [
                    5.3779,
                    43.2945,
                ],
            },
            "gps_accuracy_m": 12.0,
            "azimuth_deg": 145.2,
            "inclination_deg": -30.0,
            "camera_height_m": 2.1,
            "camera_height_source": "device_estimate",
            "camera_height_uncertainty_m": 0.1,
            "focal_length_mm": 24.0,
            "zoom_ratio": 1.0,
            "captured_at": observed_at.isoformat(),
        },
    }


def test_create_photo_report_returns_201(
    monkeypatch,
):
    repository = setup_repositories(
        monkeypatch
    )

    app.dependency_overrides[
        get_current_identity
    ] = verified_identity

    client = TestClient(app)

    client_report_id = UUID(
        "550e8400-e29b-41d4-a716-446655440001"
    )

    observed_at = (
        datetime.now(UTC)
        - timedelta(minutes=5)
    )

    response = client.post(
        "/api/v1/reports",
        json=build_photo_payload(
            client_report_id,
            observed_at,
        ),
    )

    app.dependency_overrides.clear()

    assert response.status_code == 201

    data = response.json()

    assert data["positioning_mode"] == "photo"

    assert data["final_position"] == {
        "type": "Point",
        "coordinates": [
            5.40,
            43.31,
        ],
    }

    assert len(repository.reports) == 1

    report = repository.reports[0]

    assert (
        repository.get_photo_status(
            report.id
        )
        == UploadStatus.PENDING
    )


def test_identical_photo_retry_returns_200(
    monkeypatch,
):
    repository = setup_repositories(
        monkeypatch
    )

    app.dependency_overrides[
        get_current_identity
    ] = verified_identity

    client = TestClient(app)

    client_report_id = UUID(
        "550e8400-e29b-41d4-a716-446655440002"
    )

    observed_at = (
        datetime.now(UTC)
        - timedelta(minutes=5)
    )

    payload = build_photo_payload(
        client_report_id,
        observed_at,
    )

    first = client.post(
        "/api/v1/reports",
        json=payload,
    )

    second = client.post(
        "/api/v1/reports",
        json=payload,
    )

    app.dependency_overrides.clear()

    assert first.status_code == 201
    assert second.status_code == 200

    assert (
        first.json()["id"]
        == second.json()["id"]
    )

    assert len(repository.reports) == 1


def test_photo_without_positioning_returns_422(
    monkeypatch,
):
    setup_repositories(
        monkeypatch
    )

    app.dependency_overrides[
        get_current_identity
    ] = verified_identity

    client = TestClient(app)

    observed_at = (
        datetime.now(UTC)
        - timedelta(minutes=5)
    )

    payload = build_photo_payload(
        UUID(
            "550e8400-e29b-41d4-a716-446655440003"
        ),
        observed_at,
    )

    del payload["positioning"]

    response = client.post(
        "/api/v1/reports",
        json=payload,
    )

    app.dependency_overrides.clear()

    assert response.status_code == 422


def test_photo_with_bad_gps_accuracy_returns_422(
    monkeypatch,
):
    setup_repositories(
        monkeypatch
    )

    app.dependency_overrides[
        get_current_identity
    ] = verified_identity

    client = TestClient(app)

    observed_at = (
        datetime.now(UTC)
        - timedelta(minutes=5)
    )

    payload = build_photo_payload(
        UUID(
            "550e8400-e29b-41d4-a716-446655440004"
        ),
        observed_at,
    )

    payload["positioning"][
        "gps_accuracy_m"
    ] = 50.1

    response = client.post(
        "/api/v1/reports",
        json=payload,
    )

    app.dependency_overrides.clear()

    assert response.status_code == 422

    assert (
        response.json()["error"]["code"]
        == "gps_precision_insufficient"
    )


def test_same_photo_id_with_different_data_returns_409(
    monkeypatch,
):
    repository = setup_repositories(
        monkeypatch
    )

    app.dependency_overrides[
        get_current_identity
    ] = verified_identity

    client = TestClient(app)

    client_report_id = UUID(
        "550e8400-e29b-41d4-a716-446655440005"
    )

    observed_at = (
        datetime.now(UTC)
        - timedelta(minutes=5)
    )

    first_payload = build_photo_payload(
        client_report_id,
        observed_at,
    )

    second_payload = build_photo_payload(
        client_report_id,
        observed_at,
    )

    second_payload["category"] = "obstruction"

    first = client.post(
        "/api/v1/reports",
        json=first_payload,
    )

    second = client.post(
        "/api/v1/reports",
        json=second_payload,
    )

    app.dependency_overrides.clear()

    assert first.status_code == 201
    assert second.status_code == 409

    assert (
        second.json()["error"]["code"]
        == "REPORT_CLIENT_ID_CONFLICT"
    )

    assert len(repository.reports) == 1
