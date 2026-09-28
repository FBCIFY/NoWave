from datetime import UTC, datetime
from typing import Literal

from pydantic import (
    BaseModel,
    ConfigDict,
    Field,
    FiniteFloat,
    field_validator,
)


class PositionEstimatePoint(BaseModel):
    model_config = ConfigDict(
        extra="forbid",
    )

    type: Literal["Point"]

    coordinates: list[FiniteFloat] = Field(
        min_length=2,
        max_length=2,
    )

    @field_validator("coordinates")
    @classmethod
    def validate_coordinates(
        cls,
        coordinates: list[float],
    ) -> list[float]:
        longitude, latitude = coordinates

        if not -180 <= longitude <= 180:
            raise ValueError(
                "longitude must be between -180 and 180"
            )

        if not -90 <= latitude <= 90:
            raise ValueError(
                "latitude must be between -90 and 90"
            )

        return coordinates


class PositionEstimateRequest(BaseModel):
    model_config = ConfigDict(
        extra="forbid",
    )

    observer_position: PositionEstimatePoint

    gps_accuracy_m: FiniteFloat = Field(
        ge=0,
    )

    azimuth_deg: FiniteFloat = Field(
        ge=0,
        lt=360,
    )

    inclination_deg: FiniteFloat

    camera_height_m: FiniteFloat = Field(
        gt=0,
    )

    camera_height_source: str | None = Field(
        default=None,
        max_length=30,
    )

    camera_height_uncertainty_m: (
        FiniteFloat | None
    ) = Field(
        default=None,
        ge=0,
    )

    focal_length_mm: (
        FiniteFloat | None
    ) = Field(
        default=None,
        gt=0,
    )

    zoom_ratio: (
        FiniteFloat | None
    ) = Field(
        default=None,
        gt=0,
    )

    captured_at: datetime

    @field_validator("captured_at")
    @classmethod
    def validate_captured_at(
        cls,
        captured_at: datetime,
    ) -> datetime:
        if (
            captured_at.tzinfo is None
            or captured_at.utcoffset() is None
        ):
            raise ValueError(
                "captured_at must include a timezone"
            )

        return captured_at.astimezone(UTC)


class PositionEstimateResponse(BaseModel):
    estimated_position: (
        PositionEstimatePoint
        | None
    )

    estimated_distance_m: float | None
