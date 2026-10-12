from datetime import UTC, datetime
from enum import Enum
from uuid import UUID, uuid4

from app.domain.errors import ModerationConflictError
from app.domain.report import ReportStatus
from app.domain.user import UserStatus


class ModerationActionType(str, Enum):
    REMOVE_REPORT = "remove_report"
    RESTORE_REPORT = "restore_report"
    HIDE_PHOTO = "hide_photo"
    SUSPEND_USER = "suspend_user"
    REACTIVATE_USER = "reactivate_user"


USER_ACTIONS = {
    ModerationActionType.SUSPEND_USER,
    ModerationActionType.REACTIVATE_USER,
}

REPORT_ACTIONS = {
    ModerationActionType.REMOVE_REPORT,
    ModerationActionType.RESTORE_REPORT,
}


def normalize_reason(reason: str) -> str:
    if not isinstance(reason, str):
        raise ValueError("reason must be a string")

    reason = reason.strip()

    if not reason:
        raise ValueError("reason cannot be empty")

    return reason


def removed_report_status(
    current_status: ReportStatus,
) -> ReportStatus:
    if current_status == ReportStatus.REMOVED:
        raise ModerationConflictError(
            "report is already removed"
        )

    return ReportStatus.REMOVED


def restored_report_status(
    current_status: ReportStatus,
    expires_at: datetime,
    now: datetime,
) -> ReportStatus:
    """A restoration keeps the original expiration."""
    if current_status != ReportStatus.REMOVED:
        raise ModerationConflictError(
            "report is not removed"
        )

    if expires_at > now:
        return ReportStatus.ACTIVE

    return ReportStatus.EXPIRED


def suspended_user_status(
    current_status: UserStatus,
) -> UserStatus:
    if current_status == UserStatus.SUSPENDED:
        raise ModerationConflictError(
            "user is already suspended"
        )

    return UserStatus.SUSPENDED


def reactivated_user_status(
    current_status: UserStatus,
) -> UserStatus:
    if current_status == UserStatus.ACTIVE:
        raise ModerationConflictError(
            "user is already active"
        )

    return UserStatus.ACTIVE


class ModerationAction:
    def __init__(
        self,
        admin_user_id: UUID,
        action: ModerationActionType,
        reason: str,
        target_user_id: UUID | None = None,
        target_report_id: UUID | None = None,
        target_photo_report_id: UUID | None = None,
        previous_status: str | None = None,
        new_status: str | None = None,
        id: UUID | None = None,
        created_at: datetime | None = None,
    ):
        if admin_user_id is None:
            raise ValueError("admin_user_id is required")

        action = ModerationActionType(action)

        targets = [
            target
            for target in (
                target_user_id,
                target_report_id,
                target_photo_report_id,
            )
            if target is not None
        ]

        if len(targets) != 1:
            raise ValueError(
                "exactly one target is required"
            )

        if action in USER_ACTIONS:
            expected_target = target_user_id
        elif action in REPORT_ACTIONS:
            expected_target = target_report_id
        else:
            expected_target = target_photo_report_id

        if expected_target is None:
            raise ValueError(
                "target does not match the action"
            )

        self.id = id if id is not None else uuid4()
        self.admin_user_id = admin_user_id
        self.action = action
        self.reason = normalize_reason(reason)
        self.target_user_id = target_user_id
        self.target_report_id = target_report_id
        self.target_photo_report_id = target_photo_report_id
        self.previous_status = previous_status
        self.new_status = new_status
        self.created_at = (
            created_at
            if created_at is not None
            else datetime.now(UTC)
        )
