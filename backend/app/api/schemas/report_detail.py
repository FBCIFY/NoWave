from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel

from app.api.schemas.report import GeoJSONPoint
from app.domain.report import (
    ReportCategory,
    ReportPositioningMode,
    ReportStatus,
)


class ReportDetailAuthorResponse(BaseModel):
    username: str | None
    deleted: bool


class ReportDetailBoatResponse(BaseModel):
    name: str | None
    boat_type: Literal[
        "voilier",
        "bateau_moteur",
        "catamaran",
        "semi_rigide",
        "jet_ski",
        "autre",
    ]


class ReportDetailPhotoResponse(BaseModel):
    status: Literal[
        "pending",
        "uploaded",
        "failed",
    ]
    url: str | None = None


class ReportDetailResponse(BaseModel):
    id: UUID
    version: int
    category: ReportCategory
    description: str | None
    positioning_mode: ReportPositioningMode
    final_position: GeoJSONPoint
    status: ReportStatus
    observed_at: datetime
    expires_at: datetime

    author: ReportDetailAuthorResponse | None
    boat: ReportDetailBoatResponse | None
    photo: ReportDetailPhotoResponse | None
