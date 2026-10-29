from datetime import UTC, datetime, timedelta
from uuid import uuid4

import pytest

from app.application.ports.report_detail_repository import (
    ReportDetailData,
)
from app.application.services.get_report_detail import (
    GetReportDetail,
)
from app.domain.errors import ReportNotFoundError
from app.domain.report import (
    ReportCategory,
    ReportPositioningMode,
    ReportStatus,
)


NOW = datetime(
    2026,
    9,
    30,
    8,
    0,
    tzinfo=UTC,
)


class FakeReportDetailRepository:
    def __init__(
        self,
        report: ReportDetailData | None = None,
    ):
        self.report = report

    def get_by_id(
        self,
        report_id,
    ):
        if self.report is None:
            return None

        if self.report.id != report_id:
            return None

        return self.report


def make_report_detail(
    **changes,
) -> ReportDetailData:
    values = {
        "id": uuid4(),
        "category": ReportCategory.POLLUTION,
        "positioning_mode": (
            ReportPositioningMode.MANUAL
        ),
        "description": "Pollution visible",
        "longitude": 5.37,
        "latitude": 43.29,
        "observed_at": NOW - timedelta(hours=1),
        "expires_at": NOW + timedelta(hours=23),
        "status": ReportStatus.ACTIVE,
        "version": 1,
        "author_deleted": False,
        "author_username": "Jonathan",
        "boat_name": None,
        "boat_type": None,
        "photo_status": None,
        "photo_object_key": None,
        "photo_hidden_at": None,
    }

    values.update(changes)

    return ReportDetailData(
        **values
    )


def test_active_non_expired_report_is_returned():
    report = make_report_detail()

    service = GetReportDetail(
        FakeReportDetailRepository(report)
    )

    result = service.execute(
        report_id=report.id,
        now=NOW,
    )

    assert result is report


def test_unknown_report_raises_not_found():
    service = GetReportDetail(
        FakeReportDetailRepository()
    )

    with pytest.raises(ReportNotFoundError):
        service.execute(
            report_id=uuid4(),
            now=NOW,
        )


def test_removed_report_raises_not_found():
    report = make_report_detail(
        status=ReportStatus.REMOVED,
    )

    service = GetReportDetail(
        FakeReportDetailRepository(report)
    )

    with pytest.raises(ReportNotFoundError):
        service.execute(
            report_id=report.id,
            now=NOW,
        )


def test_expired_report_raises_not_found():
    report = make_report_detail(
        expires_at=NOW - timedelta(seconds=1),
    )

    service = GetReportDetail(
        FakeReportDetailRepository(report)
    )

    with pytest.raises(ReportNotFoundError):
        service.execute(
            report_id=report.id,
            now=NOW,
        )


def test_report_is_not_visible_exactly_at_expires_at():
    report = make_report_detail(
        expires_at=NOW,
    )

    service = GetReportDetail(
        FakeReportDetailRepository(report)
    )

    with pytest.raises(ReportNotFoundError):
        service.execute(
            report_id=report.id,
            now=NOW,
        )


def test_report_is_visible_before_expires_at():
    report = make_report_detail(
        expires_at=NOW + timedelta(seconds=1),
    )

    service = GetReportDetail(
        FakeReportDetailRepository(report)
    )

    result = service.execute(
        report_id=report.id,
        now=NOW,
    )

    assert result is report


def test_naive_current_time_is_rejected():
    report = make_report_detail()

    service = GetReportDetail(
        FakeReportDetailRepository(report)
    )

    naive_now = datetime(
        2026,
        9,
        30,
        8,
        0,
    )

    with pytest.raises(
        ValueError,
        match="now must include a timezone",
    ):
        service.execute(
            report_id=report.id,
            now=naive_now,
        )
