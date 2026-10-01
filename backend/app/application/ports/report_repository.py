from abc import ABC, abstractmethod
from uuid import UUID

from app.domain.positioning import (
    PositionEstimateResult,
    PositioningMeasurements,
)
from app.domain.report import Report
from app.domain.report_photo import UploadStatus
from app.domain.report_positioning import StoredReportPositioning


class ReportRepository(ABC):
    @abstractmethod
    def get_by_client_report_id(
        self,
        author_id: UUID,
        client_report_id: UUID,
    ) -> Report | None:
        pass

    @abstractmethod
    def save(
        self,
        report: Report,
    ) -> Report | None:
        pass

    @abstractmethod
    def save_photo(
        self,
        report: Report,
        measurements: PositioningMeasurements,
        estimate: PositionEstimateResult,
    ) -> Report | None:
        pass

    @abstractmethod
    def get_photo_positioning(
        self,
        report_id: UUID,
    ) -> StoredReportPositioning | None:
        pass

    @abstractmethod
    def get_photo_status(
        self,
        report_id: UUID,
    ) -> UploadStatus | None:
        pass
