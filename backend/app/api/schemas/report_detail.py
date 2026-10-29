from datetime import datetime
from uuid import UUID

from pydantic import BaseModel

from app.api.schemas.report import GeoJSONPoint
from app.domain.boat import BoatType
from app.domain.report import (
    ReportCategory,
    ReportPositioningMode,
    ReportStatus,
)
from app.domain.report_photo import UploadStatus


class ReportDetailAuthorResponse(BaseModel):
    username: str | None
    deleted: bool


class ReportDetailBoatResponse(BaseModel):
    name: str | None
    boat_type: BoatType


class ReportDetailPhotoResponse(BaseModel):
    status: UploadStatus
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
