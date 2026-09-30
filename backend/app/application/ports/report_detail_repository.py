from abc import ABC, abstractmethod
from dataclasses import dataclass
from datetime import datetime
from uuid import UUID

from app.domain.boat import BoatType
from app.domain.report import (
    ReportCategory,
    ReportPositioningMode,
    ReportStatus,
)
from app.domain.report_photo import UploadStatus


@dataclass(frozen=True)
class ReportDetailData:
    id: UUID
    category: ReportCategory
    positioning_mode: ReportPositioningMode
    description: str | None
    longitude: float
    latitude: float
    observed_at: datetime
    expires_at: datetime
    status: ReportStatus
    version: int

    author_deleted: bool
    author_username: str | None

    boat_name: str | None
    boat_type: BoatType | None

    photo_status: UploadStatus | None
    photo_object_key: str | None
    photo_hidden_at: datetime | None


class ReportDetailRepository(ABC):
    @abstractmethod
    def get_by_id(
        self,
        report_id: UUID,
    ) -> ReportDetailData | None:
        pass
