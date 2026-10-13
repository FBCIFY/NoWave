from abc import ABC, abstractmethod
from uuid import UUID

from app.domain.alert_recipient import AlertRecipient


class AlertRecipientRepository(ABC):
    """Read alert recipients without creating notifications or sending push."""

    @abstractmethod
    def select_for_report(self, report_id: UUID) -> tuple[AlertRecipient, ...]:
        """Return one entry per eligible user, or an empty tuple if none qualify.

        Raise ReportNotFoundError if the report does not exist. Return an empty
        tuple for a removed or expired report (including expires_at <= now).

        Exclude the author and require active users with notifications enabled.
        Keep only active devices with a nonblank FCM token and a valid position
        whose accuracy is between 0 and 50 metres. The distance from the report's
        final position must be <= ALERT_RADIUS_M, measured in metres.

        Do not filter by position age, last_seen_at, or heading. Include every
        eligible device once, grouped by user. Result order is unspecified.

        This is a snapshot, not permission to send later: the worker must check
        current eligibility and report state again before delivery.
        """
        pass
