from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict

from app.domain.report import ReportCategory


class PublicObservationResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    category: ReportCategory
    longitude: float
    latitude: float
    observed_at: datetime
    expires_at: datetime
    description: str | None = None
    author_username: str | None = None


class PublicObservationPageResponse(BaseModel):
    items: list[PublicObservationResponse]
    has_more: bool
    next_cursor: str | None = None
