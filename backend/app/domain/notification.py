from dataclasses import dataclass, field
from datetime import datetime, timedelta
from email.utils import parsedate_to_datetime
import json
from math import floor
from uuid import UUID


RETRY_MINUTES = (1, 5, 15, 30, 60)
METERS_PER_NAUTICAL_MILE = 1852
NOTIFICATION_DESCRIPTION_MAX = 100
DEFAULT_NOTIFICATION_BODY = "Un signalement à proximité."
CATEGORY_LABELS = {
    "marine_animal": "Animal marin",
    "obstruction": "Obstacle",
    "pollution": "Pollution",
}


class PushSendError(Exception):
    def __init__(self, code, *, permanent=False, invalid_token=False, retry_after=None):
        super().__init__(code)
        self.code = code
        self.permanent = permanent
        self.invalid_token = invalid_token
        self.retry_after = retry_after


def parse_retry_after(value: str | None, now: datetime) -> datetime | None:
    if not value:
        return None
    try:
        if value.strip().isdigit():
            return now + timedelta(seconds=int(value))
        result = parsedate_to_datetime(value)
        return result if result.tzinfo is not None and result > now else None
    except (ValueError, TypeError, OverflowError):
        return None


def next_attempt_at(attempt_count: int, now: datetime, retry_after=None) -> datetime:
    delay = RETRY_MINUTES[min(attempt_count, len(RETRY_MINUTES) - 1)]
    scheduled = now + timedelta(minutes=delay)
    return max(scheduled, retry_after) if retry_after is not None else scheduled


def coordinate_dms(value: float, positive: str, negative: str) -> str:
    # Same rounding and carry as the mobile formatter, including 59.5 seconds.
    seconds = floor(abs(value) * 3600 + 0.5)
    degrees, seconds = divmod(seconds, 3600)
    minutes, seconds = divmod(seconds, 60)
    direction = negative if value < 0 else positive
    return f"{degrees}° {minutes}′ {seconds}″ {direction}"


def nautical_miles(distance_m: float) -> str:
    # Same thresholds and rounding as formatNauticalMiles on mobile.
    miles = distance_m / METERS_PER_NAUTICAL_MILE
    if miles < 0.1:
        return "< 0,1 NM"
    if miles < 10:
        tenths = floor(miles * 10 + 0.5)
        return f"{tenths // 10},{tenths % 10} NM"
    return f"{floor(miles + 0.5)} NM"


@dataclass(frozen=True)
class NotificationDelivery:
    notification_id: UUID
    device_id: UUID
    alert_id: UUID
    report_id: UUID
    report_version: int
    category: str
    longitude: float
    latitude: float
    distance_m: float
    alerted_at: datetime
    expires_at: datetime
    attempt_count: int
    fcm_token: str = field(repr=False)
    description: str | None = field(default=None, repr=False)

    def title(self) -> str:
        label = CATEGORY_LABELS.get(self.category, "Signalement")
        return f"{label} · {nautical_miles(self.distance_m)}"

    def body(self) -> str:
        description = " ".join((self.description or "").split())
        if not description:
            return DEFAULT_NOTIFICATION_BODY
        if len(description) > NOTIFICATION_DESCRIPTION_MAX:
            description = description[: NOTIFICATION_DESCRIPTION_MAX - 1].rstrip() + "…"
        return f"« {description} »"

    def data(self) -> dict[str, str]:
        return {
            "notification_id": str(self.notification_id),
            "alert_id": str(self.alert_id),
            "report_id": str(self.report_id),
            "report_version": str(self.report_version),
            "category": self.category,
            "distance_m": str(self.distance_m),
            "position_dms": (
                coordinate_dms(self.latitude, "N", "S")
                + " · "
                + coordinate_dms(self.longitude, "E", "W")
            ),
            "position": json.dumps(
                {"type": "Point", "coordinates": [self.longitude, self.latitude]}
            ),
            "alerted_at": self.alerted_at.isoformat(),
            "expires_at": self.expires_at.isoformat(),
        }
