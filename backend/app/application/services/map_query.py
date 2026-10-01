from uuid import UUID

from app.application.ports.map_tile_repository import MapTileRepository
from app.domain.report import ReportCategory


class MapQueryService:
    """Query report map tiles through the application boundary."""

    def __init__(self, map_tile_repository: MapTileRepository):
        self.map_tile_repository = map_tile_repository

    def get_tile(
        self,
        *,
        zoom: int,
        x: int,
        y: int,
        category: ReportCategory | None = None,
        report_id: UUID | None = None,
    ) -> bytes:
        return self.map_tile_repository.get_tile(
            zoom=zoom,
            x=x,
            y=y,
            category=category,
            report_id=report_id,
        )
