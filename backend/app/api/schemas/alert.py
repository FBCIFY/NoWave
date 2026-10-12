from datetime import datetime
from uuid import UUID

from pydantic import BaseModel

from app.api.schemas.report import GeoJSONPoint
from app.domain.report import ReportCategory


class AlertResponse(BaseModel):
    id: UUID
    report_id: UUID
    report_version: int
    category: ReportCategory
    position: GeoJSONPoint
    distance_m: float
    alerted_at: datetime
