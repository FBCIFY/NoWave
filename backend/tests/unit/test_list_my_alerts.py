from datetime import UTC, datetime
from uuid import uuid4

import pytest

from app.application.services.list_my_alerts import ListMyAlerts
from app.domain.alert import Alert
from app.domain.errors import UserNotFoundError
from app.domain.pagination import (
    DEFAULT_PAGE_LIMIT,
    MAX_PAGE,
    MAX_PAGE_LIMIT,
    Page,
)
from app.domain.report import ReportCategory
from app.domain.user import User


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


class FakeAlertHistoryRepository:
    def __init__(self, items=()):
        self.items = list(items)
        self.calls = []

    def list_for_user(self, **values):
        self.calls.append(values)

        return Page(
            items=self.items,
            page=values["page"],
            limit=values["limit"],
            total=len(self.items),
        )


def make_user():
    return User(
        firebase_uid="firebase-alerts",
        username="navigateur",
        email="alerts@nowave.test",
    )


def make_alert():
    return Alert(
        id=uuid4(),
        report_id=uuid4(),
        report_version=1,
        category=ReportCategory.MARINE_ANIMAL,
        longitude=5.37,
        latitude=43.29,
        distance_m=1250.5,
        alerted_at=datetime(2026, 10, 12, 10, 0, tzinfo=UTC),
    )


def create_service(user=None, items=()):
    alerts = FakeAlertHistoryRepository(items)

    service = ListMyAlerts(
        user_repository=FakeUserRepository(user),
        alert_history_repository=alerts,
    )

    return service, alerts


def test_lists_alerts_of_the_current_user():
    user = make_user()
    alert = make_alert()
    service, alerts = create_service(user, [alert])

    page = service.execute(
        firebase_uid=user.firebase_uid,
        page=2,
        limit=5,
    )

    assert page.items == [alert]
    assert alerts.calls == [
        {"user_id": user.id, "page": 2, "limit": 5},
    ]


def test_uses_default_pagination():
    user = make_user()
    service, alerts = create_service(user)

    service.execute(firebase_uid=user.firebase_uid)

    assert alerts.calls == [
        {
            "user_id": user.id,
            "page": 1,
            "limit": DEFAULT_PAGE_LIMIT,
        },
    ]


def test_rejects_missing_profile():
    service, alerts = create_service()

    with pytest.raises(UserNotFoundError):
        service.execute(firebase_uid="unknown")

    assert alerts.calls == []


@pytest.mark.parametrize(
    ("page", "limit"),
    [
        (0, 20),
        (MAX_PAGE + 1, 20),
        (1, 0),
        (1, MAX_PAGE_LIMIT + 1),
    ],
)
def test_rejects_invalid_pagination(page, limit):
    user = make_user()
    service, alerts = create_service(user)

    with pytest.raises(ValueError):
        service.execute(
            firebase_uid=user.firebase_uid,
            page=page,
            limit=limit,
        )

    assert alerts.calls == []
