from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Path, Query, Response

from app.api.dependencies.auth import get_current_identity
from app.application.services.map_query import MapQueryService
from app.domain.report import ReportCategory
from app.domain.marine import MarineFamily
from app.domain.marine_tile import Tile
from app.domain.marine import ProviderUnavailable
from app.infrastructure.marine.runtime import get_marine_service
from app.infrastructure.adapters.emodnet_bathymetry import (
    BathymetryUnavailable,
    fetch_bathymetry_tile,
)
from app.infrastructure.repositories.postgresql_map_tile_repository import (
    PostgreSQLMapTileRepository,
)


router = APIRouter(prefix="/map", tags=["map"])


@router.get("/seamarks/{z}/{x}/{y}.pbf")
async def get_seamark_tile(
    z: Annotated[int, Path(ge=0, le=14)],
    x: Annotated[int, Path(ge=0)],
    y: Annotated[int, Path(ge=0)],
) -> Response:
    return await _marine_tile(z, x, y, MarineFamily.SEAMARKS)


@router.get("/port-infrastructure/{z}/{x}/{y}.pbf")
async def get_port_infrastructure_tile(
    z: Annotated[int, Path(ge=0, le=14)],
    x: Annotated[int, Path(ge=0)],
    y: Annotated[int, Path(ge=0)],
) -> Response:
    return await _marine_tile(z, x, y, MarineFamily.PORTS)


async def _marine_tile(z, x, y, family):
    try:
        tile = Tile(z, x, y)
    except ValueError as error:
        raise HTTPException(
            status_code=422, detail="Invalid marine XYZ tile."
        ) from error
    try:
        result = await get_marine_service().get_tile(tile, family)
    except ProviderUnavailable as error:
        raise HTTPException(
            status_code=503, detail="Marine data temporarily unavailable."
        ) from error
    return Response(
        content=result.content,
        media_type="application/vnd.mapbox-vector-tile",
        headers={
            "Cache-Control": f"public, max-age={15 if result.failures else 300}",
            "X-NoWave-Marine-Status": "degraded" if result.failures else "ok",
            "X-NoWave-Marine-Sources": ",".join(result.sources),
            "Link": '</api/v1/map/marine-sources>; rel="describedby"',
        },
    )


@router.get("/marine-sources")
def get_marine_sources():
    from app.infrastructure.marine.sources import SOURCES

    return {
        "usage": "Display only; not for navigation. Modified and merged by NoWave.",
        "sources": SOURCES,
    }


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
        map_tile_reader=PostgreSQLMapTileRepository(),
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


@router.get("/bathymetry/{z}/{x}/{y}.png")
def get_bathymetry_tile(
    z: Annotated[int, Path(ge=0, le=14)],
    x: Annotated[int, Path(ge=0)],
    y: Annotated[int, Path(ge=0)],
) -> Response:
    """Return one visual bathymetry tile in Web Mercator."""

    tile_count = 1 << z

    if x >= tile_count or y >= tile_count:
        raise HTTPException(
            status_code=422,
            detail="Tile coordinates must be within the selected zoom level.",
        )

    try:
        tile = fetch_bathymetry_tile(z, x, y)
    except BathymetryUnavailable as error:
        raise HTTPException(
            status_code=503,
            detail="Bathymetry temporarily unavailable.",
        ) from error

    return Response(
        content=tile,
        media_type="image/png",
        headers={
            "Cache-Control": "public, max-age=86400",
        },
    )
