from datetime import UTC, datetime, timedelta
from uuid import uuid4

from fastapi.testclient import TestClient

from app.api.dependencies.auth import get_current_identity
from app.application.ports.report_detail_repository import (
    ReportDetailData,
)
from app.domain.report import (
    ReportCategory,
    ReportPositioningMode,
    ReportStatus,
)
from app.main import app


NOW = datetime.now(UTC)


class FakeReportDetailRepository:
    def __init__(self, report=None):
        self.report = report

    def get_by_id(self, report_id):
        if self.report is None:
            return None

        if self.report.id != report_id:
            return None

        return self.report


def verified_identity():
    return {
        "uid": "firebase-user-123",
        "email": "user@nowave.test",
        "email_verified": True,
    }


def make_report_detail(**changes):
    values = {
        "id": uuid4(),
        "category": ReportCategory.POLLUTION,
        "positioning_mode": ReportPositioningMode.MANUAL,
        "description": "Pollution visible",
        "longitude": 5.37,
        "latitude": 43.29,
        "observed_at": NOW - timedelta(hours=1),
        "expires_at": NOW + timedelta(hours=23),
        "status": ReportStatus.ACTIVE,
        "version": 1,
        "author_deleted": False,
        "author_username": None,
        "boat_name": None,
        "boat_type": None,
        "photo_status": None,
        "photo_object_key": None,
        "photo_hidden_at": None,
    }

    values.update(changes)

    return ReportDetailData(**values)


def setup_repository(monkeypatch, report):
    repository = FakeReportDetailRepository(report)

    monkeypatch.setattr(
        "app.api.routes.report_details."
        "PostgreSQLReportDetailRepository",
        lambda: repository,
    )


def test_get_report_detail_returns_200(monkeypatch):
    report = make_report_detail()

    setup_repository(monkeypatch, report)

    app.dependency_overrides[get_current_identity] = (
        verified_identity
    )

    client = TestClient(app)

    response = client.get(
        f"/api/v1/reports/{report.id}"
    )

    app.dependency_overrides.clear()

    assert response.status_code == 200

    data = response.json()

    assert data["id"] == str(report.id)
    assert data["category"] == "pollution"
    assert data["description"] == "Pollution visible"
    assert data["positioning_mode"] == "manual"
    assert data["status"] == "active"

    assert data["final_position"] == {
        "type": "Point",
        "coordinates": [5.37, 43.29],
    }

    assert "distance_m" not in data
    assert "author_id" not in data
    assert "client_report_id" not in data


def test_get_report_detail_requires_authentication():
    client = TestClient(app)

    response = client.get(
        f"/api/v1/reports/{uuid4()}"
    )

    assert response.status_code == 401


def test_unknown_report_returns_404(monkeypatch):
    setup_repository(
        monkeypatch,
        None,
    )

    app.dependency_overrides[get_current_identity] = (
        verified_identity
    )

    client = TestClient(app)

    response = client.get(
        f"/api/v1/reports/{uuid4()}"
    )

    app.dependency_overrides.clear()

    assert response.status_code == 404
    assert (
        response.json()["error"]["code"]
        == "report_not_found"
    )


def test_visible_author_is_returned(monkeypatch):
    report = make_report_detail(
        author_username="Jonathan",
    )

    setup_repository(monkeypatch, report)

    app.dependency_overrides[get_current_identity] = (
        verified_identity
    )

    response = TestClient(app).get(
        f"/api/v1/reports/{report.id}"
    )

    app.dependency_overrides.clear()

    assert response.status_code == 200

    assert response.json()["author"] == {
        "username": "Jonathan",
        "deleted": False,
    }


def test_hidden_author_is_not_returned(monkeypatch):
    report = make_report_detail(
        author_username=None,
        author_deleted=False,
    )

    setup_repository(monkeypatch, report)

    app.dependency_overrides[get_current_identity] = (
        verified_identity
    )

    response = TestClient(app).get(
        f"/api/v1/reports/{report.id}"
    )

    app.dependency_overrides.clear()

    assert response.status_code == 200
    assert response.json()["author"] is None


def test_deleted_author_is_identified(monkeypatch):
    report = make_report_detail(
        author_deleted=True,
        author_username=None,
    )

    setup_repository(monkeypatch, report)

    app.dependency_overrides[get_current_identity] = (
        verified_identity
    )

    response = TestClient(app).get(
        f"/api/v1/reports/{report.id}"
    )

    app.dependency_overrides.clear()

    assert response.status_code == 200

    assert response.json()["author"] == {
        "username": None,
        "deleted": True,
    }


def test_visible_boat_is_returned(monkeypatch):
    report = make_report_detail(
        boat_name="Asteria",
        boat_type="voilier",
    )

    setup_repository(monkeypatch, report)

    app.dependency_overrides[get_current_identity] = (
        verified_identity
    )

    response = TestClient(app).get(
        f"/api/v1/reports/{report.id}"
    )

    app.dependency_overrides.clear()

    assert response.status_code == 200

    assert response.json()["boat"] == {
        "name": "Asteria",
        "boat_type": "voilier",
    }


def test_manual_report_has_no_photo(monkeypatch):
    report = make_report_detail()

    setup_repository(monkeypatch, report)

    app.dependency_overrides[get_current_identity] = (
        verified_identity
    )

    response = TestClient(app).get(
        f"/api/v1/reports/{report.id}"
    )

    app.dependency_overrides.clear()

    assert response.status_code == 200
    assert response.json()["photo"] is None


def test_pending_photo_has_no_url(monkeypatch):
    report = make_report_detail(
        positioning_mode=ReportPositioningMode.PHOTO,
        photo_status="pending",
    )

    setup_repository(monkeypatch, report)

    app.dependency_overrides[get_current_identity] = (
        verified_identity
    )

    response = TestClient(app).get(
        f"/api/v1/reports/{report.id}"
    )

    app.dependency_overrides.clear()

    assert response.status_code == 200

    assert response.json()["photo"] == {
        "status": "pending",
        "url": None,
    }


def test_hidden_uploaded_photo_has_no_url(monkeypatch):
    report = make_report_detail(
        positioning_mode=ReportPositioningMode.PHOTO,
        photo_status="uploaded",
        photo_object_key="reports/photo.jpg",
        photo_hidden_at=NOW,
    )

    setup_repository(monkeypatch, report)

    app.dependency_overrides[get_current_identity] = (
        verified_identity
    )

    response = TestClient(app).get(
        f"/api/v1/reports/{report.id}"
    )

    app.dependency_overrides.clear()

    assert response.status_code == 200

    assert response.json()["photo"] == {
        "status": "uploaded",
        "url": None,
    }
