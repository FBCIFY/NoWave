from datetime import UTC, datetime, timedelta
from uuid import uuid4

import pytest

from app.application.services.create_report import CreateReport
from app.domain.errors import (
    InactiveUserError,
    ReportClientIdConflictError,
    UserNotFoundError,
)
from app.domain.report import Report, ReportCategory
from app.domain.user import User, UserStatus


class FakeUserRepository:
    def __init__(self, user=None):
        self.user = user

    def get_by_firebase_uid(self, firebase_uid):
        if self.user is None:
            return None

        if self.user.firebase_uid != firebase_uid:
            return None

        return self.user


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


def create_active_user():
    return User(
        firebase_uid="firebase-user",
        username="jonathan",
        email="jonathan@nowave.test",
    )


def test_create_report_success():
    user = create_active_user()

    user_repository = FakeUserRepository(user)
    report_repository = FakeReportRepository()

    service = CreateReport(
        user_repository=user_repository,
        report_repository=report_repository,
    )

    result = service.execute(
        firebase_uid="firebase-user",
        client_report_id=uuid4(),
        category=ReportCategory.POLLUTION,
        longitude=5.37,
        latitude=43.29,
        observed_at=datetime.now(UTC) - timedelta(minutes=5),
        description="Pollution visible",
    )

    assert result.created is True
    assert result.report.author_id == user.id
    assert result.report.category == ReportCategory.POLLUTION
    assert len(report_repository.reports) == 1


def test_create_report_user_not_found():
    service = CreateReport(
        user_repository=FakeUserRepository(),
        report_repository=FakeReportRepository(),
    )

    with pytest.raises(UserNotFoundError):
        service.execute(
            firebase_uid="unknown-user",
            client_report_id=uuid4(),
            category=ReportCategory.POLLUTION,
            longitude=5.37,
            latitude=43.29,
            observed_at=datetime.now(UTC),
        )


def test_create_report_inactive_user():
    user = create_active_user()
    user.status = UserStatus.SUSPENDED

    service = CreateReport(
        user_repository=FakeUserRepository(user),
        report_repository=FakeReportRepository(),
    )

    with pytest.raises(InactiveUserError):
        service.execute(
            firebase_uid="firebase-user",
            client_report_id=uuid4(),
            category=ReportCategory.POLLUTION,
            longitude=5.37,
            latitude=43.29,
            observed_at=datetime.now(UTC),
        )


def test_same_client_report_id_returns_existing_report():
    user = create_active_user()
    report_repository = FakeReportRepository()

    client_report_id = uuid4()
    observed_at = datetime.now(UTC) - timedelta(minutes=5)

    existing_report = Report.create_manual(
        author_id=user.id,
        client_report_id=client_report_id,
        category=ReportCategory.POLLUTION,
        longitude=5.37,
        latitude=43.29,
        observed_at=observed_at,
        description="Pollution visible",
    )

    report_repository.save(existing_report)

    service = CreateReport(
        user_repository=FakeUserRepository(user),
        report_repository=report_repository,
    )

    result = service.execute(
        firebase_uid="firebase-user",
        client_report_id=client_report_id,
        category=ReportCategory.POLLUTION,
        longitude=5.37,
        latitude=43.29,
        observed_at=observed_at,
        description="Pollution visible",
    )

    assert result.created is False
    assert result.report is existing_report
    assert len(report_repository.reports) == 1


def test_same_client_report_id_with_different_data_raises_conflict():
    user = create_active_user()
    report_repository = FakeReportRepository()

    client_report_id = uuid4()
    observed_at = datetime.now(UTC) - timedelta(minutes=5)

    existing_report = Report.create_manual(
        author_id=user.id,
        client_report_id=client_report_id,
        category=ReportCategory.POLLUTION,
        longitude=5.37,
        latitude=43.29,
        observed_at=observed_at,
        description="Pollution visible",
    )

    report_repository.save(existing_report)

    service = CreateReport(
        user_repository=FakeUserRepository(user),
        report_repository=report_repository,
    )

    with pytest.raises(ReportClientIdConflictError):
        service.execute(
            firebase_uid="firebase-user",
            client_report_id=client_report_id,
            category=ReportCategory.OBSTRUCTION,
            longitude=5.37,
            latitude=43.29,
            observed_at=observed_at,
            description="Pollution visible",
        )

    assert len(report_repository.reports) == 1
