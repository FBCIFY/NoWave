from uuid import UUID

from app.application.services.map_query import MapQueryService
from app.domain.report import ReportCategory


def test_map_query_delegates_to_repository():
    expected_tile = b"vector tile bytes"
    received = {}

    class FakeMapTileRepository:
        def get_tile(self, **kwargs):
            received.update(kwargs)
            return expected_tile

    service = MapQueryService(
        map_tile_repository=FakeMapTileRepository(),
    )

    tile = service.get_tile(
        zoom=4,
        x=8,
        y=6,
        category=ReportCategory.POLLUTION,
        report_id=UUID("550e8400-e29b-41d4-a716-446655440000"),
    )

    assert tile == expected_tile
    assert received == {
        "zoom": 4,
        "x": 8,
        "y": 6,
        "category": ReportCategory.POLLUTION,
        "report_id": UUID("550e8400-e29b-41d4-a716-446655440000"),
    }
