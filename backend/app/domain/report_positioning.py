from dataclasses import dataclass
from uuid import UUID

from app.domain.positioning import PositioningMeasurements


@dataclass(frozen=True)
class StoredReportPositioning:
    report_id: UUID
    measurements: PositioningMeasurements
    estimated_longitude: float | None
    estimated_latitude: float | None
    estimated_distance_m: float | None
    algorithm_version: str | None

    def matches_measurements(
        self,
        measurements: PositioningMeasurements,
    ) -> bool:
        return self.measurements == measurements
