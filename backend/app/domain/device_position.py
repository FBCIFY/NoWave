from datetime import UTC, datetime
from math import isfinite
from uuid import UUID

from app.domain.errors import GpsPrecisionInsufficientError


class DevicePosition:
    def __init__(
        self,
        device_id: UUID,
        longitude: float,
        latitude: float,
        accuracy_m: float,
        measured_at: datetime,
        heading_deg: float | None = None,
        received_at: datetime | None = None,
    ):
        if not isfinite(longitude):
            raise ValueError("longitude must be finite")

        if not -180 <= longitude <= 180:
            raise ValueError(
                "longitude must be between -180 and 180"
            )

        if not isfinite(latitude):
            raise ValueError("latitude must be finite")

        if not -90 <= latitude <= 90:
            raise ValueError(
                "latitude must be between -90 and 90"
            )

        if not isfinite(accuracy_m):
            raise ValueError("accuracy_m must be finite")

        if accuracy_m < 0:
            raise ValueError(
                "accuracy_m cannot be negative"
            )

        if accuracy_m > 50:
            raise GpsPrecisionInsufficientError(
                accuracy_m
            )

        if heading_deg is not None:
            if not isfinite(heading_deg):
                raise ValueError(
                    "heading_deg must be finite"
                )

            if not 0 <= heading_deg < 360:
                raise ValueError(
                    "heading_deg must be between 0 and 360"
                )

        if measured_at.tzinfo is None:
            raise ValueError(
                "measured_at must include a timezone"
            )

        self.device_id = device_id
        self.longitude = longitude
        self.latitude = latitude
        self.accuracy_m = accuracy_m
        self.heading_deg = heading_deg
        self.measured_at = measured_at
        self.received_at = (
            received_at
            if received_at is not None
            else datetime.now(UTC)
        )
