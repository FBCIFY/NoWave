from datetime import UTC, datetime
from uuid import UUID

from app.application.ports.admin_read_repository import (
    AdminReadRepository,
    AdminReportDetailData,
    AdminReportSummaryData,
    AdminUserData,
    ModerationActionData,
)
from app.domain.errors import ReportNotFoundError
from app.domain.pagination import (
    DEFAULT_PAGE_LIMIT,
    Page,
    validate_page,
)
from app.domain.report import ReportStatus
from app.domain.user import UserStatus


class AdminReadService:
    """Moderation reads. Unlike the public detail, removed and expired
    reports stay readable."""

    def __init__(
        self,
        admin_read_repository: AdminReadRepository,
    ):
        self.admin_read_repository = admin_read_repository

    def list_reports(
        self,
        page: int = 1,
        limit: int = DEFAULT_PAGE_LIMIT,
        status: ReportStatus | None = None,
        now: datetime | None = None,
    ) -> Page[AdminReportSummaryData]:
        validate_page(page, limit)

        return self.admin_read_repository.list_reports(
            page=page,
            limit=limit,
            status=status,
            now=self._now(now),
        )

    def get_report(
        self,
        report_id: UUID,
        now: datetime | None = None,
    ) -> AdminReportDetailData:
        report = self.admin_read_repository.get_report(
            report_id=report_id,
            now=self._now(now),
        )

        if report is None:
            raise ReportNotFoundError(
                "report not found"
            )

        return report

    def list_users(
        self,
        page: int = 1,
        limit: int = DEFAULT_PAGE_LIMIT,
        status: UserStatus | None = None,
    ) -> Page[AdminUserData]:
        validate_page(page, limit)

        return self.admin_read_repository.list_users(
            page=page,
            limit=limit,
            status=status,
        )

    def list_moderation_actions(
        self,
        page: int = 1,
        limit: int = DEFAULT_PAGE_LIMIT,
        report_id: UUID | None = None,
    ) -> Page[ModerationActionData]:
        validate_page(page, limit)

        return self.admin_read_repository.list_moderation_actions(
            page=page,
            limit=limit,
            report_id=report_id,
        )

    def _now(
        self,
        now: datetime | None,
    ) -> datetime:
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

        return current_time.astimezone(UTC)
