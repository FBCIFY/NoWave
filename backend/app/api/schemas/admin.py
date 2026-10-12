from typing import Literal

from pydantic import BaseModel, ConfigDict, field_validator

from app.domain.user import UserStatus


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
