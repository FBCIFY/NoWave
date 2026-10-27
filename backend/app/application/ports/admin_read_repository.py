from abc import ABC, abstractmethod
from dataclasses import dataclass
from datetime import datetime
from uuid import UUID

from app.application.ports.report_detail_repository import (
    ReportDetailData,
)
from app.domain.moderation import ModerationActionType
from app.domain.pagination import Page
from app.domain.report import (
    ReportCategory,
    ReportPositioningMode,
    ReportStatus,
)
from app.domain.report_photo import UploadStatus
from app.domain.user import UserRole, UserStatus


@dataclass(frozen=True)
class AdminReportSummaryData:
    id: UUID
    category: ReportCategory
    positioning_mode: ReportPositioningMode
    status: ReportStatus
    observed_at: datetime
    expires_at: datetime
    removed_at: datetime | None
    version: int

    author_id: UUID | None
    author_username: str | None

    photo_status: UploadStatus | None
    photo_hidden_at: datetime | None
    description: str | None = None


@dataclass(frozen=True)
class AdminReportDetailData(ReportDetailData):
    """ReportDetailData for moderation: author_username, boat_name and
    boat_type ignore the author's visibility choices."""

    removed_at: datetime | None

    author_id: UUID | None
    author_email: str | None
    author_status: UserStatus | None


@dataclass(frozen=True)
class AdminUserData:
    id: UUID
    username: str
    email: str
    role: UserRole
    status: UserStatus
    created_at: datetime
    updated_at: datetime
    reports_count: int


@dataclass(frozen=True)
class ModerationActionData:
    """An audit entry as stored. Deleting an account or a report can set
    its admin or target id to None."""

    id: UUID
    action: ModerationActionType
    admin_user_id: UUID | None
    admin_username: str | None
    target_user_id: UUID | None
    target_report_id: UUID | None
    target_photo_report_id: UUID | None
    reason: str
    previous_status: str | None
    new_status: str | None
    created_at: datetime


class AdminReadRepository(ABC):
    """Read-only views for moderation. Report statuses are effective:
    an active report whose expires_at is not after now is expired."""

    @abstractmethod
    def list_reports(
        self,
        page: int,
        limit: int,
        status: ReportStatus | None,
        now: datetime,
        search: str = "",
    ) -> Page[AdminReportSummaryData]:
        pass

    @abstractmethod
    def get_report(
        self,
        report_id: UUID,
        now: datetime,
    ) -> AdminReportDetailData | None:
        pass

    @abstractmethod
    def list_users(
        self,
        page: int,
        limit: int,
        status: UserStatus | None,
    ) -> Page[AdminUserData]:
        pass

    @abstractmethod
    def list_moderation_actions(
        self,
        page: int,
        limit: int,
        report_id: UUID | None = None,
    ) -> Page[ModerationActionData]:
        pass
