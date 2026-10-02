from datetime import datetime
from math import isfinite
from typing import Literal
from uuid import UUID

from pydantic import (
    BaseModel,
    ConfigDict,
    Field,
    field_validator,
)

from app.domain.device import DevicePlatform


class DeviceRegisterRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    installation_id: UUID
    platform: DevicePlatform
    fcm_token: str | None = Field(
        default=None,
        min_length=1,
    )

    @field_validator("fcm_token")
    @classmethod
    def validate_fcm_token(
        cls,
        value: str | None,
    ) -> str | None:
        if value is None:
            return None

        value = value.strip()

        if not value:
            raise ValueError(
                "fcm_token cannot be empty"
            )

        return value


class DeviceResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    installation_id: UUID
    platform: DevicePlatform
    is_active: bool
    last_seen_at: datetime


class GeoPoint(BaseModel):
    model_config = ConfigDict(extra="forbid")

    type: Literal["Point"]
    coordinates: tuple[float, float]

    @field_validator("coordinates")
    @classmethod
    def validate_coordinates(
        cls,
        coordinates: tuple[float, float],
    ) -> tuple[float, float]:
        longitude, latitude = coordinates

        if not isfinite(longitude):
            raise ValueError(
                "longitude must be finite"
            )

        if not -180 <= longitude <= 180:
            raise ValueError(
                "longitude must be between -180 and 180"
            )

        if not isfinite(latitude):
            raise ValueError(
                "latitude must be finite"
            )

        if not -90 <= latitude <= 90:
            raise ValueError(
                "latitude must be between -90 and 90"
            )

        return coordinates


class DevicePositionRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    position: GeoPoint
    accuracy_m: float = Field(ge=0)
    heading_deg: float | None = Field(
        default=None,
        ge=0,
        lt=360,
    )
    measured_at: datetime

    @field_validator("accuracy_m")
    @classmethod
    def accuracy_m_must_be_finite(
        cls,
        accuracy_m: float,
    ) -> float:
        if not isfinite(accuracy_m):
            raise ValueError(
                "accuracy_m must be finite"
            )

        return accuracy_m

    @field_validator("heading_deg")
    @classmethod
    def heading_must_be_finite(
        cls,
        heading_deg: float | None,
    ) -> float | None:
        if (
            heading_deg is not None
            and not isfinite(heading_deg)
        ):
            raise ValueError(
                "heading_deg must be finite"
            )

        return heading_deg

    @field_validator("measured_at")
    @classmethod
    def measured_at_requires_timezone(
        cls,
        measured_at: datetime,
    ) -> datetime:
        if measured_at.tzinfo is None:
            raise ValueError(
                "measured_at must include a timezone"
            )

        return measured_at


class DevicePositionResponse(BaseModel):
    position: GeoPoint
    accuracy_m: float
    heading_deg: float | None
    measured_at: datetime
    received_at: datetime
