from datetime import UTC, datetime
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

import app.api.dependencies.auth as auth_dependency
from app.domain.alert import Alert
from app.domain.pagination import (
    DEFAULT_PAGE_LIMIT,
    MAX_PAGE,
    MAX_PAGE_LIMIT,
    Page,
)
from app.domain.report import ReportCategory
from app.domain.user import User, UserStatus
from app.main import app


client = TestClient(app)

PATH = "/api/v1/users/me/alerts"


class FakeUserRepository:
    def __init__(self, user):
        self.user = user
        self.reads = []

    def get_by_firebase_uid(self, firebase_uid):
        self.reads.append(firebase_uid)

        if self.user.firebase_uid == firebase_uid:
            return self.user

        return None


class FakeAlertHistoryRepository:
    def __init__(self, items=(), total=None):
        self.items = list(items)
        self.total = total
        self.calls = []

    def list_for_user(self, **values):
        self.calls.append(values)

        return Page(
            items=self.items,
            page=values["page"],
            limit=values["limit"],
            total=(
                self.total
                if self.total is not None
                else len(self.items)
            ),
        )


def make_user(**changes):
    values = {
        "firebase_uid": "firebase-alerts",
        "username": "navigateur",
        "email": "alerts@nowave.test",
    }
    values.update(changes)

    return User(**values)


def make_alert():
    return Alert(
        id=uuid4(),
        report_id=uuid4(),
        report_version=2,
        category=ReportCategory.OBSTRUCTION,
        longitude=5.37,
        latitude=43.29,
        distance_m=1250.5,
        alerted_at=datetime(2026, 9, 13, 10, 0, 3, tzinfo=UTC),
    )


def configure(monkeypatch, user, alerts):
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
    monkeypatch.setattr(
        "app.api.routes.users.PostgreSQLUserRepository",
        lambda: FakeUserRepository(user),
    )
    monkeypatch.setattr(
        "app.api.routes.users.PostgreSQLAlertHistoryRepository",
        lambda: alerts,
    )


def get(**params):
    return client.get(
        PATH,
        params=params,
        headers={"Authorization": "Bearer valid-token"},
    )


def test_my_alerts_require_token():
    response = client.get(PATH)

    assert response.status_code == 401
    assert response.json()["error"]["code"] == (
        "authentication_required"
    )


def test_my_alerts_reject_suspended_user(monkeypatch):
    alerts = FakeAlertHistoryRepository()
    configure(
        monkeypatch,
        make_user(status=UserStatus.SUSPENDED),
        alerts,
    )

    response = get()

    assert response.status_code == 403
    assert response.json()["error"]["code"] == "user_inactive"
    assert alerts.calls == []


def test_my_alerts_use_default_pagination(monkeypatch):
    user = make_user()
    alerts = FakeAlertHistoryRepository()
    configure(monkeypatch, user, alerts)

    response = get()

    assert response.status_code == 200
    assert response.json() == {
        "items": [],
        "page": 1,
        "limit": DEFAULT_PAGE_LIMIT,
        "total": 0,
        "pages": 0,
    }
    assert alerts.calls == [
        {
            "user_id": user.id,
            "page": 1,
            "limit": DEFAULT_PAGE_LIMIT,
        },
    ]


def test_my_alerts_read_the_profile_once(monkeypatch):
    user = make_user()
    users = FakeUserRepository(user)
    alerts = FakeAlertHistoryRepository()
    configure(monkeypatch, user, alerts)
    monkeypatch.setattr(
        auth_dependency,
        "PostgreSQLUserRepository",
        lambda: users,
    )
    monkeypatch.setattr(
        "app.api.routes.users.PostgreSQLUserRepository",
        lambda: users,
    )

    response = get()

    assert response.status_code == 200
    assert users.reads == [user.firebase_uid]


def test_my_alerts_follow_the_history_contract(monkeypatch):
    user = make_user()
    alert = make_alert()
    alerts = FakeAlertHistoryRepository([alert], total=3)
    configure(monkeypatch, user, alerts)

    response = get(page=2, limit=2)

    assert response.status_code == 200
    assert response.json() == {
        "items": [
            {
                "id": str(alert.id),
                "report_id": str(alert.report_id),
                "report_version": 2,
                "category": "obstruction",
                "position": {
                    "type": "Point",
                    "coordinates": [5.37, 43.29],
                },
                "distance_m": 1250.5,
                "alerted_at": "2026-09-13T10:00:03Z",
            },
        ],
        "page": 2,
        "limit": 2,
        "total": 3,
        "pages": 2,
    }
    assert alerts.calls == [
        {"user_id": user.id, "page": 2, "limit": 2},
    ]


@pytest.mark.parametrize(
    "params",
    [
        {"page": 0},
        {"page": MAX_PAGE + 1},
        {"limit": 0},
        {"limit": MAX_PAGE_LIMIT + 1},
        {"page": "abc"},
    ],
)
def test_my_alerts_reject_invalid_pagination(monkeypatch, params):
    alerts = FakeAlertHistoryRepository()
    configure(monkeypatch, make_user(), alerts)

    response = get(**params)

    assert response.status_code == 422
    assert response.json()["error"]["code"] == (
        "request_validation_error"
    )
    assert alerts.calls == []
