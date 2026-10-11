from datetime import UTC, datetime, timedelta
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

import app.api.dependencies.auth as auth_dependency
from app.api.dependencies.auth import get_current_admin
from app.application.ports.admin_read_repository import (
    AdminReportDetailData,
    AdminReportSummaryData,
    AdminUserData,
    ModerationActionData,
)
from app.domain.boat import BoatType
from app.domain.moderation import ModerationActionType
from app.domain.pagination import Page
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

READ_PATHS = [
    "/api/v1/admin/reports",
    "/api/v1/admin/reports/{id}",
    "/api/v1/admin/users",
    "/api/v1/admin/moderation-actions",
]

LIST_PATHS = [
    "/api/v1/admin/reports",
    "/api/v1/admin/users",
    "/api/v1/admin/moderation-actions",
]


class FakeAdminReadRepository:
    def __init__(
        self,
        reports=(),
        report=None,
        users=(),
        actions=(),
        total=None,
    ):
        self.reports = list(reports)
        self.report = report
        self.users = list(users)
        self.actions = list(actions)
        self.total = total
        self.calls = []

    def _page(self, name, items, values):
        self.calls.append((name, values))

        return Page(
            items=items,
            page=values["page"],
            limit=values["limit"],
            total=(
                self.total
                if self.total is not None
                else len(items)
            ),
        )

    def list_reports(self, **values):
        return self._page("list_reports", self.reports, values)

    def get_report(self, **values):
        self.calls.append(("get_report", values))
        return self.report

    def list_users(self, **values):
        return self._page("list_users", self.users, values)

    def list_moderation_actions(self, **values):
        return self._page(
            "list_moderation_actions",
            self.actions,
            values,
        )


class FakeUserRepository:
    def __init__(self, user=None):
        self.user = user

    def get_by_firebase_uid(self, firebase_uid):
        return self.user


def make_user(**changes):
    values = {
        "firebase_uid": "firebase-user",
        "username": "navigateur",
        "email": "user@nowave.test",
    }
    values.update(changes)

    return User(**values)


def make_report_summary(**changes):
    values = {
        "id": uuid4(),
        "category": ReportCategory.POLLUTION,
        "positioning_mode": ReportPositioningMode.PHOTO,
        "status": ReportStatus.REMOVED,
        "observed_at": NOW - timedelta(hours=2),
        "expires_at": NOW + timedelta(hours=22),
        "removed_at": NOW - timedelta(hours=1),
        "version": 1,
        "author_id": uuid4(),
        "author_username": "navigateur",
        "photo_status": UploadStatus.UPLOADED,
        "photo_hidden_at": None,
    }
    values.update(changes)

    return AdminReportSummaryData(**values)


def make_report_detail(**changes):
    values = {
        "id": uuid4(),
        "category": ReportCategory.POLLUTION,
        "positioning_mode": ReportPositioningMode.PHOTO,
        "description": "Nappe visible",
        "longitude": 5.37,
        "latitude": 43.29,
        "observed_at": NOW - timedelta(hours=30),
        "expires_at": NOW - timedelta(hours=6),
        "status": ReportStatus.EXPIRED,
        "version": 2,
        "author_deleted": False,
        "author_username": "navigateur",
        "boat_name": "Sea Explorer",
        "boat_type": BoatType("voilier"),
        "photo_status": UploadStatus.UPLOADED,
        "photo_object_key": "reports/photo.jpg",
        "photo_hidden_at": None,
        "removed_at": None,
        "author_id": uuid4(),
        "author_email": "user@nowave.test",
        "author_status": UserStatus.SUSPENDED,
    }
    values.update(changes)

    return AdminReportDetailData(**values)


def make_admin_user(**changes):
    values = {
        "id": uuid4(),
        "username": "navigateur",
        "email": "user@nowave.test",
        "role": UserRole.USER,
        "status": UserStatus.SUSPENDED,
        "created_at": NOW - timedelta(days=30),
        "updated_at": NOW,
        "reports_count": 6,
    }
    values.update(changes)

    return AdminUserData(**values)


def make_action(**changes):
    values = {
        "id": uuid4(),
        "action": ModerationActionType.SUSPEND_USER,
        "admin_user_id": uuid4(),
        "admin_username": "admin",
        "target_user_id": uuid4(),
        "target_report_id": None,
        "target_photo_report_id": None,
        "reason": "Signalements abusifs répétés",
        "previous_status": "active",
        "new_status": "suspended",
        "created_at": NOW,
    }
    values.update(changes)

    return ModerationActionData(**values)


@pytest.fixture
def admin():
    admin = make_user(
        firebase_uid="firebase-admin",
        username="admin",
        email="admin@nowave.test",
        role=UserRole.ADMIN,
    )
    app.dependency_overrides[get_current_admin] = lambda: admin

    yield admin

    app.dependency_overrides.clear()


def setup_repository(monkeypatch, repository):
    monkeypatch.setattr(
        "app.api.routes.admin.PostgreSQLAdminReadRepository",
        lambda: repository,
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


def get(path, **params):
    return client.get(
        path.format(id=uuid4()),
        params=params,
        headers={"Authorization": "Bearer valid-token"},
    )


@pytest.mark.parametrize("path", READ_PATHS)
def test_admin_reads_require_token(path):
    response = client.get(path.format(id=uuid4()))

    assert response.status_code == 401
    assert response.json()["error"]["code"] == (
        "authentication_required"
    )


@pytest.mark.parametrize("path", READ_PATHS)
def test_admin_reads_reject_non_admin(monkeypatch, path):
    repository = FakeAdminReadRepository()
    setup_repository(monkeypatch, repository)
    configure_auth(monkeypatch, make_user())

    response = get(path)

    assert response.status_code == 403
    assert response.json()["error"]["code"] == "admin_required"
    assert repository.calls == []


@pytest.mark.parametrize("path", READ_PATHS)
def test_admin_reads_reject_suspended_admin(monkeypatch, path):
    repository = FakeAdminReadRepository()
    setup_repository(monkeypatch, repository)
    configure_auth(
        monkeypatch,
        make_user(
            role=UserRole.ADMIN,
            status=UserStatus.SUSPENDED,
        ),
    )

    response = get(path)

    assert response.status_code == 403
    assert response.json()["error"]["code"] == "user_inactive"
    assert repository.calls == []


@pytest.mark.parametrize("path", LIST_PATHS)
def test_lists_use_default_pagination(monkeypatch, admin, path):
    repository = FakeAdminReadRepository()
    setup_repository(monkeypatch, repository)

    response = get(path)

    assert response.status_code == 200
    assert response.json() == {
        "items": [],
        "page": 1,
        "limit": 20,
        "total": 0,
        "pages": 0,
    }
    assert repository.calls[0][1]["page"] == 1
    assert repository.calls[0][1]["limit"] == 20


@pytest.mark.parametrize("path", LIST_PATHS)
@pytest.mark.parametrize(
    "params",
    [
        {"page": 0},
        {"page": -1},
        {"page": "x"},
        {"page": 1_000_001},
        {"limit": 0},
        {"limit": 101},
    ],
)
def test_lists_reject_invalid_pagination(
    monkeypatch,
    admin,
    path,
    params,
):
    repository = FakeAdminReadRepository()
    setup_repository(monkeypatch, repository)

    response = get(path, **params)

    assert response.status_code == 422
    assert response.json()["error"]["code"] == (
        "request_validation_error"
    )
    assert repository.calls == []


def test_list_reports_contract(monkeypatch, admin):
    report = make_report_summary()
    repository = FakeAdminReadRepository(
        reports=[report],
        total=41,
    )
    setup_repository(monkeypatch, repository)

    response = get(
        "/api/v1/admin/reports",
        page=2,
        limit=20,
        status="removed",
    )

    assert response.status_code == 200
    body = response.json()

    assert body["page"] == 2
    assert body["limit"] == 20
    assert body["total"] == 41
    assert body["pages"] == 3
    assert body["items"] == [
        {
            "id": str(report.id),
            "category": "pollution",
            "positioning_mode": "photo",
            "status": "removed",
            "observed_at": report.observed_at.isoformat().replace(
                "+00:00", "Z"
            ),
            "expires_at": report.expires_at.isoformat().replace(
                "+00:00", "Z"
            ),
            "removed_at": report.removed_at.isoformat().replace(
                "+00:00", "Z"
            ),
            "version": 1,
            "author_id": str(report.author_id),
            "author_username": "navigateur",
            "photo_status": "uploaded",
            "photo_hidden_at": None,
        }
    ]

    name, values = repository.calls[0]

    assert name == "list_reports"
    assert values["status"] == ReportStatus.REMOVED
    assert values["now"].tzinfo == UTC


def test_list_reports_rejects_unknown_status(monkeypatch, admin):
    repository = FakeAdminReadRepository()
    setup_repository(monkeypatch, repository)

    response = get("/api/v1/admin/reports", status="hidden")

    assert response.status_code == 422
    assert repository.calls == []


def test_report_detail_shows_expired_report_with_photo_url(
    monkeypatch,
    admin,
):
    report = make_report_detail()
    repository = FakeAdminReadRepository(report=report)
    setup_repository(monkeypatch, repository)

    class FakeStorage:
        def create_read_url(self, object_key, expires_in):
            assert object_key == "reports/photo.jpg"
            assert expires_in.total_seconds() == 300
            return "https://signed.test/reports/photo.jpg"

    monkeypatch.setattr(
        "app.api.routes.report_details.get_photo_storage",
        FakeStorage,
    )

    response = get(f"/api/v1/admin/reports/{report.id}")

    assert response.status_code == 200
    body = response.json()

    assert body["id"] == str(report.id)
    assert body["status"] == "expired"
    assert body["removed_at"] is None
    assert body["final_position"] == {
        "type": "Point",
        "coordinates": [5.37, 43.29],
    }
    assert body["author"] == {
        "id": str(report.author_id),
        "username": "navigateur",
        "email": "user@nowave.test",
        "status": "suspended",
        "deleted": False,
    }
    assert body["boat"] == {
        "name": "Sea Explorer",
        "boat_type": "voilier",
    }
    assert body["photo"] == {
        "status": "uploaded",
        "url": "https://signed.test/reports/photo.jpg",
        "hidden_at": None,
    }
    assert repository.calls[0][1]["report_id"] == report.id


def test_report_detail_never_signs_hidden_photo(monkeypatch, admin):
    hidden_at = NOW - timedelta(minutes=10)
    report = make_report_detail(
        status=ReportStatus.REMOVED,
        removed_at=NOW - timedelta(minutes=5),
        photo_hidden_at=hidden_at,
    )
    setup_repository(
        monkeypatch,
        FakeAdminReadRepository(report=report),
    )

    def forbidden_storage():
        raise AssertionError("hidden photo must not be signed")

    monkeypatch.setattr(
        "app.api.routes.report_details.get_photo_storage",
        forbidden_storage,
    )

    response = get(f"/api/v1/admin/reports/{report.id}")

    assert response.status_code == 200
    body = response.json()

    assert body["status"] == "removed"
    assert body["removed_at"] is not None
    assert body["photo"]["url"] is None
    assert body["photo"]["hidden_at"] is not None


def test_report_detail_with_deleted_author(monkeypatch, admin):
    report = make_report_detail(
        author_deleted=True,
        author_id=None,
        author_username=None,
        author_email=None,
        author_status=None,
        boat_name=None,
        boat_type=None,
        photo_status=None,
        photo_object_key=None,
    )
    setup_repository(
        monkeypatch,
        FakeAdminReadRepository(report=report),
    )

    response = get(f"/api/v1/admin/reports/{report.id}")

    assert response.status_code == 200
    body = response.json()

    assert body["author"] == {
        "id": None,
        "username": None,
        "email": None,
        "status": None,
        "deleted": True,
    }
    assert body["boat"] is None
    assert body["photo"] is None


def test_report_detail_missing_returns_404(monkeypatch, admin):
    setup_repository(monkeypatch, FakeAdminReadRepository())

    response = get("/api/v1/admin/reports/{id}")

    assert response.status_code == 404
    assert response.json()["error"]["code"] == "report_not_found"


def test_report_detail_rejects_invalid_id(monkeypatch, admin):
    repository = FakeAdminReadRepository()
    setup_repository(monkeypatch, repository)

    response = get("/api/v1/admin/reports/not-a-uuid")

    assert response.status_code == 422
    assert repository.calls == []


def test_list_users_contract(monkeypatch, admin):
    user = make_admin_user()
    repository = FakeAdminReadRepository(users=[user])
    setup_repository(monkeypatch, repository)

    response = get(
        "/api/v1/admin/users",
        status="suspended",
        limit=5,
    )

    assert response.status_code == 200
    body = response.json()

    assert body["limit"] == 5
    assert body["total"] == 1
    assert body["pages"] == 1
    assert set(body["items"][0]) == {
        "id",
        "username",
        "email",
        "role",
        "status",
        "created_at",
        "updated_at",
        "reports_count",
    }
    assert body["items"][0]["status"] == "suspended"
    assert body["items"][0]["reports_count"] == 6
    assert repository.calls[0][1]["status"] == UserStatus.SUSPENDED


def test_list_users_rejects_unknown_status(monkeypatch, admin):
    repository = FakeAdminReadRepository()
    setup_repository(monkeypatch, repository)

    response = get("/api/v1/admin/users", status="banned")

    assert response.status_code == 422
    assert repository.calls == []


def test_list_moderation_actions_contract(monkeypatch, admin):
    action = make_action()
    orphan = make_action(
        action=ModerationActionType.REMOVE_REPORT,
        admin_user_id=None,
        admin_username=None,
        target_user_id=None,
        previous_status=None,
        new_status=None,
    )
    repository = FakeAdminReadRepository(
        actions=[action, orphan],
    )
    setup_repository(monkeypatch, repository)

    response = get("/api/v1/admin/moderation-actions")

    assert response.status_code == 200
    items = response.json()["items"]

    assert items[0] == {
        "id": str(action.id),
        "action": "suspend_user",
        "admin_user_id": str(action.admin_user_id),
        "admin_username": "admin",
        "target_user_id": str(action.target_user_id),
        "target_report_id": None,
        "target_photo_report_id": None,
        "reason": "Signalements abusifs répétés",
        "previous_status": "active",
        "new_status": "suspended",
        "created_at": action.created_at.isoformat().replace(
            "+00:00", "Z"
        ),
    }
    assert items[1]["admin_user_id"] is None
    assert items[1]["target_user_id"] is None


@pytest.mark.parametrize(
    "method",
    ["POST", "PUT", "PATCH", "DELETE"],
)
def test_moderation_actions_are_read_only(admin, method):
    response = client.request(
        method,
        "/api/v1/admin/moderation-actions",
        json={"reason": "Motif"},
        headers={"Authorization": "Bearer valid-token"},
    )

    assert response.status_code == 405
