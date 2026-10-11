from datetime import datetime
from typing import Generic, Literal, TypeVar
from uuid import UUID

from pydantic import BaseModel, ConfigDict, field_validator

from app.api.schemas.report_detail import (
    ReportDetailPhotoResponse,
    ReportDetailResponse,
)
from app.domain.moderation import ModerationActionType
from app.domain.report import (
    ReportCategory,
    ReportPositioningMode,
    ReportStatus,
)
from app.domain.report_photo import UploadStatus
from app.domain.user import UserRole, UserStatus


T = TypeVar("T")


class ModerationReasonRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    reason: str

    @field_validator("reason")
    @classmethod
    def clean_reason(cls, reason: str) -> str:
        reason = reason.strip()

        if not reason:
            raise ValueError("reason cannot be empty")

        return reason


class ReportRestoreRequest(ModerationReasonRequest):
    status: Literal["active"]


class PhotoHideRequest(ModerationReasonRequest):
    hidden: Literal[True]


class UserStatusUpdateRequest(ModerationReasonRequest):
    status: UserStatus


class PaginatedResponse(BaseModel, Generic[T]):
    items: list[T]
    page: int
    limit: int
    total: int
    pages: int


class AdminReportSummaryResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

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


class AdminReportAuthorResponse(BaseModel):
    id: UUID | None
    username: str | None
    email: str | None
    status: UserStatus | None
    deleted: bool


class AdminReportPhotoResponse(ReportDetailPhotoResponse):
    hidden_at: datetime | None


class AdminReportDetailResponse(ReportDetailResponse):
    """ReportDetail plus the moderation state. The author and the boat
    are shown whatever the author's visibility choices."""

    removed_at: datetime | None
    author: AdminReportAuthorResponse
    photo: AdminReportPhotoResponse | None


class AdminUserResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    username: str
    email: str
    role: UserRole
    status: UserStatus
    created_at: datetime
    updated_at: datetime
    reports_count: int


class ModerationActionResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

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
