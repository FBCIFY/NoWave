from datetime import UTC, datetime, timedelta
from uuid import uuid4

import pytest

from app.domain.report import (
    Report,
    ReportCategory,
    ReportPositioningMode,
    ReportStatus,
)
from app.domain.user import User
from app.infrastructure.repositories.postgresql_report_repository import (
    PostgreSQLReportRepository,
)
from app.infrastructure.repositories.postgresql_user_repository import (
    PostgreSQLUserRepository,
)


def test_report_repository_save_and_get(dsn, monkeypatch):
    monkeypatch.setenv("DATABASE_URL", dsn)

    user_repository = PostgreSQLUserRepository()
    report_repository = PostgreSQLReportRepository()

    user = User(
        firebase_uid="firebase-report-repository",
        username="report-repository-user",
        email="report-repository@nowave.test",
    )

    user_repository.save(user)

    observed_at = datetime.now(UTC) - timedelta(minutes=5)

    report = Report.create_manual(
        author_id=user.id,
        client_report_id=uuid4(),
        category=ReportCategory.POLLUTION,
        longitude=5.37,
        latitude=43.29,
        observed_at=observed_at,
        description="Pollution de surface visible",
    )

    saved_report = report_repository.save(report)

    assert saved_report.id == report.id
    assert saved_report.author_id == user.id
    assert saved_report.category == ReportCategory.POLLUTION
    assert saved_report.positioning_mode == ReportPositioningMode.MANUAL
    assert saved_report.status == ReportStatus.ACTIVE
    assert saved_report.longitude == pytest.approx(5.37)
    assert saved_report.latitude == pytest.approx(43.29)

    found_report = report_repository.get_by_client_report_id(
        author_id=user.id,
        client_report_id=report.client_report_id,
    )

    assert found_report is not None
    assert found_report.id == report.id
    assert found_report.client_report_id == report.client_report_id
    assert found_report.category == ReportCategory.POLLUTION
    assert found_report.description == "Pollution de surface visible"
    assert found_report.longitude == pytest.approx(5.37)
    assert found_report.latitude == pytest.approx(43.29)


def test_report_repository_returns_none_when_not_found(
    dsn,
    monkeypatch,
):
    monkeypatch.setenv("DATABASE_URL", dsn)

    repository = PostgreSQLReportRepository()

    result = repository.get_by_client_report_id(
        author_id=uuid4(),
        client_report_id=uuid4(),
    )

    assert result is None
