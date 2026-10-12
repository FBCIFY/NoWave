from datetime import UTC, datetime
from uuid import UUID

from app.application.ports.moderation_repository import (
    HiddenPhotoData,
    ModerationRepository,
)
from app.application.ports.report_detail_repository import (
    ReportDetailData,
    ReportDetailRepository,
)
from app.domain.errors import (
    ModerationConflictError,
    ReportNotFoundError,
)
from app.domain.moderation import normalize_reason
from app.domain.user import User


class ModerationService:
    """The five moderation actions. Each one requires a non-empty reason
    and writes its change and its audit entry together."""

    def __init__(
        self,
        moderation_repository: ModerationRepository,
        report_detail_repository: ReportDetailRepository,
    ):
        self.moderation_repository = moderation_repository
        self.report_detail_repository = report_detail_repository

    def remove_report(
        self,
        admin: User,
        report_id: UUID,
        reason: str,
        now: datetime | None = None,
    ) -> None:
        self.moderation_repository.remove_report(
            report_id=report_id,
            admin_user_id=admin.id,
            reason=normalize_reason(reason),
            now=self._now(now),
        )

    def restore_report(
        self,
        admin: User,
        report_id: UUID,
        reason: str,
        now: datetime | None = None,
    ) -> ReportDetailData:
        self.moderation_repository.restore_report(
            report_id=report_id,
            admin_user_id=admin.id,
            reason=normalize_reason(reason),
            now=self._now(now),
        )

        report = self.report_detail_repository.get_by_id(
            report_id
        )

        if report is None:
            raise ReportNotFoundError(
                "report not found"
            )

        return report

    def hide_photo(
        self,
        admin: User,
        report_id: UUID,
        reason: str,
        now: datetime | None = None,
    ) -> HiddenPhotoData:
        return self.moderation_repository.hide_photo(
            report_id=report_id,
            admin_user_id=admin.id,
            reason=normalize_reason(reason),
            now=self._now(now),
        )

    def suspend_user(
        self,
        admin: User,
        user_id: UUID,
        reason: str,
        now: datetime | None = None,
    ) -> User:
        if user_id == admin.id:
            raise ModerationConflictError(
                "administrators cannot suspend their own account"
            )

        return self.moderation_repository.suspend_user(
            user_id=user_id,
            admin_user_id=admin.id,
            reason=normalize_reason(reason),
            now=self._now(now),
        )

    def reactivate_user(
        self,
        admin: User,
        user_id: UUID,
        reason: str,
        now: datetime | None = None,
    ) -> User:
        return self.moderation_repository.reactivate_user(
            user_id=user_id,
            admin_user_id=admin.id,
            reason=normalize_reason(reason),
            now=self._now(now),
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
