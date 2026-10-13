from dataclasses import dataclass, field
from math import isfinite
from uuid import UUID


ALERT_RADIUS_M = 18_520


@dataclass(frozen=True)
class RecipientDevice:
    """An eligible device and its distance from the report, in metres."""

    device_id: UUID
    fcm_token: str = field(repr=False)
    distance_m: float

    def __post_init__(self) -> None:
        if not self.fcm_token.strip():
            raise ValueError("fcm_token cannot be empty")

        if not isfinite(self.distance_m) or not 0 <= self.distance_m <= ALERT_RADIUS_M:
            raise ValueError("device distance must be between 0 and 18520 metres")


@dataclass(frozen=True)
class AlertRecipient:
    """One user with all their eligible devices, each included once."""

    user_id: UUID
    devices: tuple[RecipientDevice, ...]

    def __post_init__(self) -> None:
        if not self.devices:
            raise ValueError("a recipient must have at least one eligible device")

        device_ids = [device.device_id for device in self.devices]
        if len(device_ids) != len(set(device_ids)):
            raise ValueError("recipient devices must be distinct")

    @property
    def distance_m(self) -> float:
        return min(device.distance_m for device in self.devices)
