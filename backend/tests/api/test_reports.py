from datetime import UTC, datetime, timedelta
from uuid import UUID

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


class FakeReportRepository:
    def __init__(self):
        self.reports = []

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


def verified_identity():
    return {
        "uid": "firebase-user-123",
        "email": "user@nowave.test",
        "email_verified": True,
    }


def build_payload(
    client_report_id,
    observed_at,
    category="pollution",
):
    return {
        "client_report_id": str(client_report_id),
        "category": category,
        "description": "Pollution de surface visible",
        "final_position": {
            "type": "Point",
            "coordinates": [
                5.37,
                43.29,
            ],
        },
        "observed_at": observed_at.isoformat(),
    }


def setup_repositories(monkeypatch):
    user = User(
        firebase_uid="firebase-user-123",
        username="Jonathan",
        email="user@nowave.test",
    )

    user_repository = FakeUserRepository(
        users=[user],
    )

    report_repository = FakeReportRepository()

    monkeypatch.setattr(
        "app.api.routes.reports.PostgreSQLUserRepository",
        lambda: user_repository,
    )

    monkeypatch.setattr(
        "app.api.routes.reports.PostgreSQLReportRepository",
        lambda: report_repository,
    )

    return report_repository


def test_create_report_returns_201(monkeypatch):
    report_repository = setup_repositories(monkeypatch)

    app.dependency_overrides[get_current_identity] = verified_identity

    client = TestClient(app)

    client_report_id = UUID(
        "550e8400-e29b-41d4-a716-446655440000"
    )

    observed_at = datetime.now(UTC) - timedelta(minutes=5)

    response = client.post(
        "/api/v1/reports",
        json=build_payload(
            client_report_id,
            observed_at,
        ),
    )

    app.dependency_overrides.clear()

    assert response.status_code == 201

    data = response.json()

    assert data["client_report_id"] == str(client_report_id)
    assert data["category"] == "pollution"
    assert data["positioning_mode"] == "manual"
    assert data["status"] == "active"

    assert data["final_position"] == {
        "type": "Point",
        "coordinates": [
            5.37,
            43.29,
        ],
    }

    assert len(report_repository.reports) == 1


def test_repeated_identical_report_returns_200(monkeypatch):
    report_repository = setup_repositories(monkeypatch)

    app.dependency_overrides[get_current_identity] = verified_identity

    client = TestClient(app)

    client_report_id = UUID(
        "550e8400-e29b-41d4-a716-446655440000"
    )

    observed_at = datetime.now(UTC) - timedelta(minutes=5)

    payload = build_payload(
        client_report_id,
        observed_at,
    )

    first_response = client.post(
        "/api/v1/reports",
        json=payload,
    )

    second_response = client.post(
        "/api/v1/reports",
        json=payload,
    )

    app.dependency_overrides.clear()

    assert first_response.status_code == 201
    assert second_response.status_code == 200

    assert len(report_repository.reports) == 1

    assert (
        second_response.json()["id"]
        == first_response.json()["id"]
    )


def test_same_client_report_id_with_different_data_returns_409(
    monkeypatch,
):
    report_repository = setup_repositories(monkeypatch)

    app.dependency_overrides[get_current_identity] = verified_identity

    client = TestClient(app)

    client_report_id = UUID(
        "550e8400-e29b-41d4-a716-446655440000"
    )

    observed_at = datetime.now(UTC) - timedelta(minutes=5)

    first_response = client.post(
        "/api/v1/reports",
        json=build_payload(
            client_report_id,
            observed_at,
            category="pollution",
        ),
    )

    conflict_response = client.post(
        "/api/v1/reports",
        json=build_payload(
            client_report_id,
            observed_at,
            category="obstruction",
        ),
    )

    app.dependency_overrides.clear()

    assert first_response.status_code == 201
    assert conflict_response.status_code == 409

    data = conflict_response.json()

    assert (
        data["error"]["code"]
        == "report_client_id_conflict"
    )

    assert len(report_repository.reports) == 1

EXPECTED_REPORT_RESPONSE_FIELDS = {
    "id",
    "author_id",
    "client_report_id",
    "category",
    "positioning_mode",
    "description",
    "final_position",
    "observed_at",
    "expires_at",
    "status",
    "version",
    "created_at",
    "updated_at",
    "photo",
}


def test_repeated_report_returns_same_response_contract(
    monkeypatch,
):
    report_repository = setup_repositories(
        monkeypatch
    )

    app.dependency_overrides[
        get_current_identity
    ] = verified_identity

    client = TestClient(app)

    client_report_id = UUID(
        "550e8400-e29b-41d4-a716-446655440010"
    )

    observed_at = (
        datetime.now(UTC)
        - timedelta(minutes=5)
    )

    payload = build_payload(
        client_report_id,
        observed_at,
    )

    try:
        first = client.post(
            "/api/v1/reports",
            json=payload,
        )

        retry = client.post(
            "/api/v1/reports",
            json=payload,
        )
    finally:
        app.dependency_overrides.clear()

    assert first.status_code == 201
    assert retry.status_code == 200

    first_data = first.json()
    retry_data = retry.json()

    assert (
        set(first_data)
        == EXPECTED_REPORT_RESPONSE_FIELDS
    )

    assert retry_data == first_data
    assert len(report_repository.reports) == 1


def test_invalid_report_position_returns_422(
    monkeypatch,
):
    setup_repositories(monkeypatch)

    app.dependency_overrides[
        get_current_identity
    ] = verified_identity

    payload = build_payload(
        UUID(
            "550e8400-e29b-41d4-a716-446655440011"
        ),
        datetime.now(UTC) - timedelta(minutes=5),
    )

    payload["final_position"]["coordinates"] = [
        181.0,
        43.29,
    ]

    try:
        response = TestClient(app).post(
            "/api/v1/reports",
            json=payload,
        )
    finally:
        app.dependency_overrides.clear()

    assert response.status_code == 422
    assert (
        response.json()["error"]["code"]
        == "invalid_report_position"
    )


def test_old_observed_at_returns_422(
    monkeypatch,
):
    setup_repositories(monkeypatch)

    app.dependency_overrides[
        get_current_identity
    ] = verified_identity

    payload = build_payload(
        UUID(
            "550e8400-e29b-41d4-a716-446655440012"
        ),
        datetime.now(UTC) - timedelta(hours=25),
    )

    try:
        response = TestClient(app).post(
            "/api/v1/reports",
            json=payload,
        )
    finally:
        app.dependency_overrides.clear()

    assert response.status_code == 422
    assert (
        response.json()["error"]["code"]
        == "invalid_observed_at"
    )


def test_description_250_character_limit_is_preserved(
    monkeypatch,
):
    setup_repositories(monkeypatch)

    app.dependency_overrides[
        get_current_identity
    ] = verified_identity

    payload = build_payload(
        UUID(
            "550e8400-e29b-41d4-a716-446655440013"
        ),
        datetime.now(UTC) - timedelta(minutes=5),
    )

    payload["description"] = "a" * 251

    try:
        response = TestClient(app).post(
            "/api/v1/reports",
            json=payload,
        )
    finally:
        app.dependency_overrides.clear()

    assert response.status_code == 422
    assert (
        response.json()["error"]["code"]
        == "request_validation_error"
    )
