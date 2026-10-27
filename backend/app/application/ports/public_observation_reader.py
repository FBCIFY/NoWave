from abc import ABC, abstractmethod
from dataclasses import dataclass
from datetime import datetime
from uuid import UUID

from app.domain.report import ReportCategory


@dataclass(frozen=True)
class PublicObservation:
    """The complete allowlist of information shown on the public map."""

    id: UUID
    category: ReportCategory
    longitude: float
    latitude: float
    observed_at: datetime
    expires_at: datetime
    description: str | None = None
    author_username: str | None = None


@dataclass(frozen=True)
class ObservationQuery:
    west: float = -180
    south: float = -90
    east: float = 180
    north: float = 90
    category: ReportCategory | None = None
    q: str = ""
    limit: int = 200
    after: tuple[datetime, UUID] | None = None


class PublicObservationReader(ABC):
    @abstractmethod
    def list_active(self, query: ObservationQuery) -> list[PublicObservation]:
        """Read at most limit + 1 active, unexpired, nonremoved observations.

        Sort by observed_at DESC, id DESC. Only consented public usernames may
        be included or searched. A west > east box crosses the antimeridian.
        """
