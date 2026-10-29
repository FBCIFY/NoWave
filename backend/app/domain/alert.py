from dataclasses import dataclass
from datetime import datetime
from math import isfinite
from uuid import UUID

from app.domain.report import ReportCategory


# 10 NM: only used to select the recipients of a publication.
ALERT_RADIUS_M = 18_520


@dataclass(frozen=True)
class AlertRecipient:
    """One user chosen by the recipient selection (NW-122)."""

    user_id: UUID

    # Smallest distance among the user's eligible devices.
    distance_m: float

    # Eligible devices, distinct, at least one.
    device_ids: tuple[UUID, ...]

    def __post_init__(self):
        if (
            not isfinite(self.distance_m)
            or self.distance_m < 0
        ):
            raise ValueError(
                "distance_m must be a finite number >= 0"
            )

        if not self.device_ids:
            raise ValueError(
                "an alert recipient needs at least one device"
            )

        if len(set(self.device_ids)) != len(self.device_ids):
            raise ValueError(
                "device_ids must be distinct"
            )


@dataclass(frozen=True)
class Alert:
    """History entry: a snapshot of the report version that was
    alerted. It has no read state and survives a failed push."""

    id: UUID
    report_id: UUID
    report_version: int
    category: ReportCategory
    longitude: float
    latitude: float
    distance_m: float
    alerted_at: datetime
