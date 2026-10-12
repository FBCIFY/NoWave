from datetime import UTC, datetime, timedelta
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

import app.api.dependencies.auth as auth_dependency
from app.api.dependencies.auth import get_current_admin
from app.application.ports.moderation_repository import (
    HiddenPhotoData,
)
from app.application.ports.report_detail_repository import (
    ReportDetailData,
)
from app.domain.errors import (
    AdminRequiredError,
    ModerationConflictError,
    PhotoNotFoundError,
    ReportNotFoundError,
    UserNotFoundError,
)
from app.domain.report import (
    ReportCategory,
    ReportPositioningMode,
    ReportStatus,
)
from app.domain.report_photo import UploadStatus
from app.domain.user import User, UserRole, UserStatus
from app.main import app


client = TestClient(app)

NOW = datetime.now(UTC)


class FakeModerationRepository:
    def __init__(self, error=None, user=None):
        self.error = error
        self.user = user
        self.calls = []

    def _call(self, name, values):
        self.calls.append((name, values))

        if self.error is not None:
            raise self.error

    def remove_report(self, **values):
        self._call("remove_report", values)

    def restore_report(self, **values):
        self._call("restore_report", values)

    def hide_photo(self, **values):
        self._call("hide_photo", values)

        return HiddenPhotoData(
            report_id=values["report_id"],
            upload_status=UploadStatus.UPLOADED,
            size_bytes=1200,
            mime_type="image/jpeg",
            hidden_at=values["now"],
        )

    def suspend_user(self, **values):
        self._call("suspend_user", values)
        return self.user

    def reactivate_user(self, **values):
        self._call("reactivate_user", values)
        return self.user


class FakeReportDetailRepository:
    def __init__(self, report=None):
        self.report = report

    def get_by_id(self, report_id):
        return self.report


class FakeUserRepository:
    def __init__(self, user=None):
        self.user = user

    def get_by_firebase_uid(self, firebase_uid):
        return self.user


def make_admin():
    return User(
        firebase_uid="firebase-admin",
        username="admin",
        email="admin@nowave.test",
        role=UserRole.ADMIN,
    )


def make_user(**changes):
    values = {
        "firebase_uid": "firebase-user",
        "username": "navigateur",
        "email": "user@nowave.test",
    }
    values.update(changes)

    return User(**values)


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


@pytest.fixture
def admin():
    admin = make_admin()
    app.dependency_overrides[get_current_admin] = lambda: admin

    yield admin

    app.dependency_overrides.clear()


def setup_repositories(
    monkeypatch,
    moderation_repository,
    report=None,
):
    monkeypatch.setattr(
        "app.api.routes.admin.PostgreSQLModerationRepository",
        lambda: moderation_repository,
    )
    monkeypatch.setattr(
        "app.api.routes.admin.PostgreSQLReportDetailRepository",
        lambda: FakeReportDetailRepository(report),
    )


def configure_auth(monkeypatch, user):
    class FakeFirebaseAuthAdapter:
        def verify_token(self, token: str) -> dict:
            return {
                "uid": user.firebase_uid,
                "email": user.email,
                "email_verified": True,
            }

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


MODERATION_REQUESTS = [
    ("delete", "/api/v1/admin/reports/{id}", {}),
    ("patch", "/api/v1/admin/reports/{id}", {"status": "active"}),
    ("patch", "/api/v1/admin/reports/{id}/photo", {"hidden": True}),
    ("patch", "/api/v1/admin/users/{id}", {"status": "suspended"}),
    ("patch", "/api/v1/admin/users/{id}", {"status": "active"}),
]


def send(method, path, body):
    return client.request(
        method.upper(),
        path.format(id=uuid4()),
        json=body,
        headers={"Authorization": "Bearer valid-token"},
    )


@pytest.mark.parametrize("method,path,body", MODERATION_REQUESTS)
def test_moderation_requires_token(method, path, body):
    response = client.request(
        method.upper(),
        path.format(id=uuid4()),
        json={**body, "reason": "Motif"},
    )

    assert response.status_code == 401
    assert response.json()["error"]["code"] == (
        "authentication_required"
    )


@pytest.mark.parametrize("method,path,body", MODERATION_REQUESTS)
def test_moderation_rejects_non_admin(
    monkeypatch,
    method,
    path,
    body,
):
    repository = FakeModerationRepository()
    setup_repositories(monkeypatch, repository)
    configure_auth(monkeypatch, make_user())

    response = send(method, path, {**body, "reason": "Motif"})

    assert response.status_code == 403
    assert response.json()["error"]["code"] == "admin_required"
    assert repository.calls == []


@pytest.mark.parametrize("method,path,body", MODERATION_REQUESTS)
def test_moderation_rejects_suspended_admin(
    monkeypatch,
    method,
    path,
    body,
):
    repository = FakeModerationRepository()
    setup_repositories(monkeypatch, repository)
    configure_auth(
        monkeypatch,
        make_user(
            role=UserRole.ADMIN,
            status=UserStatus.SUSPENDED,
        ),
    )

    response = send(method, path, {**body, "reason": "Motif"})

    assert response.status_code == 403
    assert response.json()["error"]["code"] == "user_inactive"
    assert repository.calls == []


@pytest.mark.parametrize("method,path,body", MODERATION_REQUESTS)
@pytest.mark.parametrize("reason", [None, "", "   "])
def test_moderation_rejects_blank_reason(
    monkeypatch,
    admin,
    method,
    path,
    body,
    reason,
):
    repository = FakeModerationRepository()
    setup_repositories(monkeypatch, repository)

    if reason is not None:
        body = {**body, "reason": reason}

    response = send(method, path, body)

    assert response.status_code == 422
    assert response.json()["error"]["code"] == (
        "request_validation_error"
    )
    assert repository.calls == []


def test_remove_report_returns_204(monkeypatch, admin):
    repository = FakeModerationRepository()
    setup_repositories(monkeypatch, repository)
    report_id = uuid4()

    response = client.request(
        "DELETE",
        f"/api/v1/admin/reports/{report_id}",
        json={"reason": "  Faux signalement confirmé  "},
    )

    assert response.status_code == 204
    assert response.content == b""

    name, values = repository.calls[0]

    assert name == "remove_report"
    assert values["report_id"] == report_id
    assert values["admin_user_id"] == admin.id
    assert values["reason"] == "Faux signalement confirmé"


def test_remove_report_missing_returns_404(monkeypatch, admin):
    setup_repositories(
        monkeypatch,
        FakeModerationRepository(
            error=ReportNotFoundError("report not found")
        ),
    )

    response = send(
        "delete",
        "/api/v1/admin/reports/{id}",
        {"reason": "Faux"},
    )

    assert response.status_code == 404
    assert response.json()["error"]["code"] == "report_not_found"


def test_remove_removed_report_returns_409(monkeypatch, admin):
    setup_repositories(
        monkeypatch,
        FakeModerationRepository(
            error=ModerationConflictError(
                "report is already removed"
            )
        ),
    )

    response = send(
        "delete",
        "/api/v1/admin/reports/{id}",
        {"reason": "Faux"},
    )

    assert response.status_code == 409
    assert response.json() == {
        "error": {
            "code": "moderation_conflict",
            "message": "report is already removed",
            "details": None,
        }
    }


def test_restore_report_returns_report_detail(monkeypatch, admin):
    report = make_report_detail()
    repository = FakeModerationRepository()
    setup_repositories(monkeypatch, repository, report)

    response = client.patch(
        f"/api/v1/admin/reports/{report.id}",
        json={
            "status": "active",
            "reason": "Signalement vérifié après examen",
        },
    )

    assert response.status_code == 200
    assert response.json()["id"] == str(report.id)
    assert response.json()["status"] == "active"
    assert response.json()["final_position"] == {
        "type": "Point",
        "coordinates": [5.37, 43.29],
    }
    assert repository.calls[0][0] == "restore_report"


def test_restore_report_rejects_other_status(monkeypatch, admin):
    repository = FakeModerationRepository()
    setup_repositories(monkeypatch, repository)

    response = send(
        "patch",
        "/api/v1/admin/reports/{id}",
        {"status": "removed", "reason": "Motif"},
    )

    assert response.status_code == 422
    assert repository.calls == []


def test_restore_report_hides_url_of_hidden_photo(
    monkeypatch,
    admin,
):
    class FailingPhotoStorage:
        def create_read_url(self, object_key, expires_in):
            raise AssertionError("no URL for a hidden photo")

    report = make_report_detail(
        positioning_mode=ReportPositioningMode.PHOTO,
        photo_status=UploadStatus.UPLOADED,
        photo_object_key="reports/photo.jpg",
        photo_hidden_at=NOW,
    )
    setup_repositories(
        monkeypatch,
        FakeModerationRepository(),
        report,
    )
    monkeypatch.setattr(
        "app.api.routes.report_details.get_photo_storage",
        FailingPhotoStorage,
    )

    response = client.patch(
        f"/api/v1/admin/reports/{report.id}",
        json={"status": "active", "reason": "Vérifié"},
    )

    assert response.status_code == 200
    assert response.json()["photo"] == {
        "status": "uploaded",
        "url": None,
    }


def test_hide_photo_returns_photo_metadata(monkeypatch, admin):
    repository = FakeModerationRepository()
    setup_repositories(monkeypatch, repository)
    report_id = uuid4()

    response = client.patch(
        f"/api/v1/admin/reports/{report_id}/photo",
        json={
            "hidden": True,
            "reason": "La photo enfreint les règles de modération",
        },
    )

    assert response.status_code == 200
    assert response.json() == {
        "report_id": str(report_id),
        "upload_status": "uploaded",
        "size_bytes": 1200,
        "mime_type": "image/jpeg",
    }
    assert repository.calls[0][0] == "hide_photo"


def test_hide_photo_rejects_hidden_false(monkeypatch, admin):
    repository = FakeModerationRepository()
    setup_repositories(monkeypatch, repository)

    response = send(
        "patch",
        "/api/v1/admin/reports/{id}/photo",
        {"hidden": False, "reason": "Motif"},
    )

    assert response.status_code == 422
    assert repository.calls == []


def test_hide_missing_photo_returns_404(monkeypatch, admin):
    setup_repositories(
        monkeypatch,
        FakeModerationRepository(
            error=PhotoNotFoundError("report has no photo")
        ),
    )

    response = send(
        "patch",
        "/api/v1/admin/reports/{id}/photo",
        {"hidden": True, "reason": "Motif"},
    )

    assert response.status_code == 404
    assert response.json()["error"]["code"] == "photo_not_found"


def test_suspend_user_returns_user_profile(monkeypatch, admin):
    user = make_user(status=UserStatus.SUSPENDED)
    repository = FakeModerationRepository(user=user)
    setup_repositories(monkeypatch, repository)

    response = client.patch(
        f"/api/v1/admin/users/{user.id}",
        json={
            "status": "suspended",
            "reason": "Signalements abusifs répétés",
        },
    )

    assert response.status_code == 200
    assert response.json()["id"] == str(user.id)
    assert response.json()["status"] == "suspended"
    assert "email" not in response.json()
    assert repository.calls[0][0] == "suspend_user"


def test_reactivate_user_returns_user_profile(monkeypatch, admin):
    user = make_user()
    repository = FakeModerationRepository(user=user)
    setup_repositories(monkeypatch, repository)

    response = client.patch(
        f"/api/v1/admin/users/{user.id}",
        json={
            "status": "active",
            "reason": "Compte examiné et suspension levée",
        },
    )

    assert response.status_code == 200
    assert response.json()["status"] == "active"
    assert repository.calls[0][0] == "reactivate_user"


def test_admin_cannot_suspend_self(monkeypatch, admin):
    repository = FakeModerationRepository()
    setup_repositories(monkeypatch, repository)

    response = client.patch(
        f"/api/v1/admin/users/{admin.id}",
        json={"status": "suspended", "reason": "Test"},
    )

    assert response.status_code == 409
    assert response.json()["error"]["code"] == (
        "moderation_conflict"
    )
    assert repository.calls == []


def test_update_missing_user_returns_404(monkeypatch, admin):
    setup_repositories(
        monkeypatch,
        FakeModerationRepository(
            error=UserNotFoundError("user not found")
        ),
    )

    response = send(
        "patch",
        "/api/v1/admin/users/{id}",
        {"status": "suspended", "reason": "Abus"},
    )

    assert response.status_code == 404
    assert response.json()["error"]["code"] == "user_not_found"


def test_admin_suspended_during_action_returns_403(
    monkeypatch,
    admin,
):
    setup_repositories(
        monkeypatch,
        FakeModerationRepository(
            error=AdminRequiredError(
                "an active administrator is required"
            )
        ),
    )

    response = send(
        "delete",
        "/api/v1/admin/reports/{id}",
        {"reason": "Faux"},
    )

    assert response.status_code == 403
    assert response.json()["error"]["code"] == "admin_required"


def test_moderation_rejects_unknown_fields(monkeypatch, admin):
    repository = FakeModerationRepository()
    setup_repositories(monkeypatch, repository)

    response = send(
        "delete",
        "/api/v1/admin/reports/{id}",
        {"reason": "Faux", "admin_user_id": str(uuid4())},
    )

    assert response.status_code == 422
    assert repository.calls == []
