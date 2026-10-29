from datetime import UTC, datetime
from uuid import UUID

from app.application.ports.report_detail_repository import (
    ReportDetailData,
    ReportDetailRepository,
)
from app.domain.errors import ReportNotFoundError
from app.domain.report import ReportStatus


class GetReportDetail:
    def __init__(
        self,
        report_detail_repository: ReportDetailRepository,
    ):
        self.report_detail_repository = (
            report_detail_repository
        )

    def execute(
        self,
        report_id: UUID,
        now: datetime | None = None,
    ) -> ReportDetailData:
        report = (
            self.report_detail_repository.get_by_id(
                report_id
            )
        )

        if report is None:
            raise ReportNotFoundError(
                "report not found"
            )

        current_time = (
            now
            if now is not None
            else datetime.now(UTC)
        )

        if (
            current_time.tzinfo is None
            or current_time.utcoffset() is None
        ):
            raise ValueError(
                "now must include a timezone"
            )

        current_time = current_time.astimezone(UTC)

        if report.status != ReportStatus.ACTIVE:
            raise ReportNotFoundError(
                "report not found"
            )

        if report.expires_at <= current_time:
            raise ReportNotFoundError(
                "report not found"
            )

        return report
