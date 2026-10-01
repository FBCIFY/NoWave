from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import (
    BaseModel,
    ConfigDict,
    Field,
    model_validator,
)

from app.api.schemas.position_estimate import (
    PositionEstimateRequest,
)
from app.domain.report import (
    ReportCategory,
    ReportPositioningMode,
    ReportStatus,
)


class GeoJSONPoint(BaseModel):
    model_config = ConfigDict(
        extra="forbid"
    )

    type: Literal["Point"]

    coordinates: list[float] = Field(
        min_length=2,
        max_length=2,
    )


class ReportCreateRequest(BaseModel):
    model_config = ConfigDict(
        extra="forbid"
    )

    client_report_id: UUID
    category: ReportCategory

    positioning_mode: ReportPositioningMode = (
        ReportPositioningMode.MANUAL
    )

    description: str | None = Field(
        default=None,
        max_length=250,
    )

    final_position: GeoJSONPoint

    observed_at: datetime

    positioning: PositionEstimateRequest | None = None

    @model_validator(mode="after")
    def validate_positioning(
        self,
    ):
        if (
            self.positioning_mode
            == ReportPositioningMode.PHOTO
            and self.positioning is None
        ):
            raise ValueError(
                "photo mode requires positioning data"
            )

        if (
            self.positioning_mode
            == ReportPositioningMode.MANUAL
            and self.positioning is not None
        ):
            raise ValueError(
                "manual mode cannot contain positioning data"
            )

        return self


class ReportPhotoResponse(BaseModel):
    status: str
    url: str | None = None


class ReportResponse(BaseModel):
    id: UUID
    author_id: UUID | None
    client_report_id: UUID
    category: ReportCategory
    positioning_mode: ReportPositioningMode
    description: str | None
    final_position: GeoJSONPoint
    observed_at: datetime
    expires_at: datetime
    status: ReportStatus
    version: int
    created_at: datetime
    updated_at: datetime
    photo: ReportPhotoResponse | None = None
