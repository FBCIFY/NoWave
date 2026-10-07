from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

import pytest

import app.domain.report as report_module
from app.domain.errors import InvalidObservedAtError
from app.domain.report import (
    REPORT_LIFETIME,
    Report,
    ReportCategory,
    ReportPositioningMode,
    ReportStatus,
)


def test_create_manual_report():
    author_id = uuid4()
    client_report_id = uuid4()
    observed_at = datetime.now(UTC) - timedelta(minutes=5)

    report = Report.create_manual(
        author_id=author_id,
        client_report_id=client_report_id,
        category=ReportCategory.POLLUTION,
        longitude=5.37,
        latitude=43.29,
        observed_at=observed_at,
        description="Pollution de surface visible",
    )

    assert isinstance(report.id, UUID)

    assert report.author_id == author_id
    assert report.client_report_id == client_report_id

    assert report.category == ReportCategory.POLLUTION
    assert report.description == "Pollution de surface visible"

    assert report.longitude == 5.37
    assert report.latitude == 43.29

    assert report.observed_at == observed_at
    assert report.expires_at == observed_at + timedelta(hours=24)

    assert report.positioning_mode == ReportPositioningMode.MANUAL
    assert report.status == ReportStatus.ACTIVE
    assert report.version == 1

    assert isinstance(report.created_at, datetime)
    assert isinstance(report.updated_at, datetime)

    assert report.removed_at is None

SERVER_TIME = datetime(
    2026,
    10,
    7,
    12,
    0,
    0,
    tzinfo=UTC,
)


def create_boundary_report(
    factory_name,
    observed_at,
):
    factory = getattr(
        Report,
        factory_name,
    )

    return factory(
        author_id=uuid4(),
        client_report_id=uuid4(),
        category=ReportCategory.POLLUTION,
        longitude=5.37,
        latitude=43.29,
        observed_at=observed_at,
        description="Boundary test",
    )


@pytest.mark.parametrize(
    "factory_name",
    [
        "create_manual",
        "create_photo",
    ],
)
def test_creation_accepts_just_before_24h_boundary(
    monkeypatch,
    factory_name,
):
    monkeypatch.setattr(
        report_module,
        "utc_now",
        lambda: SERVER_TIME,
    )

    observed_at = (
        SERVER_TIME
        - REPORT_LIFETIME
        + timedelta(microseconds=1)
    )

    report = create_boundary_report(
        factory_name,
        observed_at,
    )

    assert report.status == ReportStatus.ACTIVE
    assert report.expires_at > SERVER_TIME
    assert (
        report.expires_at
        == SERVER_TIME + timedelta(microseconds=1)
    )


@pytest.mark.parametrize(
    "factory_name",
    [
        "create_manual",
        "create_photo",
    ],
)
def test_creation_rejects_exact_24h_boundary(
    monkeypatch,
    factory_name,
):
    monkeypatch.setattr(
        report_module,
        "utc_now",
        lambda: SERVER_TIME,
    )

    observed_at = (
        SERVER_TIME - REPORT_LIFETIME
    )

    with pytest.raises(
        InvalidObservedAtError
    ):
        create_boundary_report(
            factory_name,
            observed_at,
        )


@pytest.mark.parametrize(
    "factory_name",
    [
        "create_manual",
        "create_photo",
    ],
)
def test_creation_rejects_after_24h_boundary(
    monkeypatch,
    factory_name,
):
    monkeypatch.setattr(
        report_module,
        "utc_now",
        lambda: SERVER_TIME,
    )

    observed_at = (
        SERVER_TIME
        - REPORT_LIFETIME
        - timedelta(microseconds=1)
    )

    with pytest.raises(
        InvalidObservedAtError
    ):
        create_boundary_report(
            factory_name,
            observed_at,
        )
