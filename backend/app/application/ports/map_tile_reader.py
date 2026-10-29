from abc import ABC, abstractmethod
from uuid import UUID

from app.domain.report import ReportCategory


class MapTileReader(ABC):
    """Read encoded map tiles independently of their storage implementation."""

    @abstractmethod
    def get_tile(
        self,
        *,
        zoom: int,
        x: int,
        y: int,
        category: ReportCategory | None = None,
        report_id: UUID | None = None,
    ) -> bytes:
        pass
