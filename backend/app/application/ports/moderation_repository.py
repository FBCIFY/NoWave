from abc import ABC, abstractmethod
from dataclasses import dataclass
from datetime import datetime
from uuid import UUID

from app.domain.moderation import ModerationAction
from app.domain.report_photo import UploadStatus
from app.domain.user import User


@dataclass(frozen=True)
class HiddenPhotoData:
    report_id: UUID
    upload_status: UploadStatus
    size_bytes: int
    mime_type: str
    hidden_at: datetime


class ModerationRepository(ABC):
    """Each method locks its target, changes it and writes its audit entry
    in one transaction. A domain error raised on the way rolls back both.

    Raise AdminRequiredError if the administrator is no longer active.
    """

    @abstractmethod
    def remove_report(
        self,
        report_id: UUID,
        admin_user_id: UUID,
        reason: str,
        now: datetime,
    ) -> ModerationAction:
        """Raise ReportNotFoundError or ModerationConflictError."""
        pass

    @abstractmethod
    def restore_report(
        self,
        report_id: UUID,
        admin_user_id: UUID,
        reason: str,
        now: datetime,
    ) -> ModerationAction:
        """Raise ReportNotFoundError or ModerationConflictError."""
        pass

    @abstractmethod
    def hide_photo(
        self,
        report_id: UUID,
        admin_user_id: UUID,
        reason: str,
        now: datetime,
    ) -> HiddenPhotoData:
        """Raise ReportNotFoundError, PhotoNotFoundError or
        ModerationConflictError."""
        pass

    @abstractmethod
    def suspend_user(
        self,
        user_id: UUID,
        admin_user_id: UUID,
        reason: str,
        now: datetime,
    ) -> User:
        """Raise UserNotFoundError or ModerationConflictError."""
        pass

    @abstractmethod
    def reactivate_user(
        self,
        user_id: UUID,
        admin_user_id: UUID,
        reason: str,
        now: datetime,
    ) -> User:
        """Raise UserNotFoundError or ModerationConflictError."""
        pass
