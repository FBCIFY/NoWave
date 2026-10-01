from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Path, Query, Response

from app.api.dependencies.auth import get_current_identity
from app.application.services.map_query import MapQueryService
from app.domain.report import ReportCategory
from app.infrastructure.repositories.postgresql_map_tile_repository import (
    PostgreSQLMapTileRepository,
)


router = APIRouter(prefix="/map", tags=["map"])


@router.get("/tiles/{z}/{x}/{y}.mvt")
def get_map_tile(
    z: Annotated[int, Path(ge=0, le=22)],
    x: Annotated[int, Path(ge=0)],
    y: Annotated[int, Path(ge=0)],
    category: Annotated[ReportCategory | None, Query()] = None,
    report_id: Annotated[UUID | None, Query()] = None,
    _identity: dict = Depends(get_current_identity),
) -> Response:
    """Return active reports for one Web Mercator map tile."""
    tile_count = 1 << z
    if x >= tile_count or y >= tile_count:
        raise HTTPException(
            status_code=422,
            detail="Tile coordinates must be within the selected zoom level.",
        )

    service = MapQueryService(
        map_tile_repository=PostgreSQLMapTileRepository(),
    )
    tile = service.get_tile(
        zoom=z,
        x=x,
        y=y,
        category=category,
        report_id=report_id,
    )

    return Response(
        content=tile,
        media_type="application/vnd.mapbox-vector-tile",
        headers={
            "Cache-Control": "private, max-age=15, must-revalidate",
            "Vary": "Authorization",
        },
    )
