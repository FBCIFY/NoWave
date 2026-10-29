import asyncio
import logging
import time
from contextlib import suppress
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Path, Query, Request, Response
from fastapi.responses import JSONResponse
from starlette.concurrency import run_in_threadpool

from app.api.dependencies.auth import get_current_identity
from app.application.services.map_query import MapQueryService
from app.domain.report import ReportCategory
from app.domain.marine import MarineFamily
from app.domain.marine_tile import Tile
from app.domain.marine import ProviderUnavailable
from app.infrastructure.marine.runtime import (
    get_marine_service, get_coastline_mask, get_bathymetry_cache,
)
from app.infrastructure.marine.coastline import has_raster_data
from app.infrastructure.marine.bathymetry_cache import UncachedBathymetryTile
from app.infrastructure.marine.visual_water import crop_context, render_visual_water
from app.infrastructure.adapters.emodnet_bathymetry import (
    BathymetryUnavailable,
    empty_bathymetry_tile,
    fetch_bathymetry_tile,
    has_bathymetry_coverage,
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


@router.get("/harbours/{z}/{x}/{y}.pbf")
async def get_harbour_tile(
    z: Annotated[int, Path(ge=0, le=14)],
    x: Annotated[int, Path(ge=0)],
    y: Annotated[int, Path(ge=0)],
) -> Response:
    return await _marine_tile(z, x, y, MarineFamily.HARBOURS)


@router.get("/depth-contours/{z}/{x}/{y}.pbf")
async def get_depth_contour_tile(
    z: Annotated[int, Path(ge=0, le=16)],
    x: Annotated[int, Path(ge=0)],
    y: Annotated[int, Path(ge=0)],
) -> Response:
    return await _marine_tile(z, x, y, MarineFamily.CONTOURS)


@router.get("/soundings/{z}/{x}/{y}.pbf")
async def get_sounding_tile(
    request: Request,
    z: Annotated[int, Path(ge=0, le=16)],
    x: Annotated[int, Path(ge=0)],
    y: Annotated[int, Path(ge=0)],
) -> Response:
    # ASGI does not automatically cancel route work on HTTP disconnect.
    work = asyncio.create_task(_marine_tile(z, x, y, MarineFamily.SOUNDINGS))
    try:
        while not work.done():
            if await request.is_disconnected():
                raise HTTPException(status_code=499, detail="Tile request cancelled.")
            await asyncio.wait({work}, timeout=0.1)
        return await work
    finally:
        if not work.done():
            work.cancel()
            with suppress(asyncio.CancelledError):
                await work


@router.get("/underwater-hazards/{z}/{x}/{y}.pbf")
async def get_underwater_hazard_tile(
    z: Annotated[int, Path(ge=0, le=16)],
    x: Annotated[int, Path(ge=0)],
    y: Annotated[int, Path(ge=0)],
) -> Response:
    return await _marine_tile(z, x, y, MarineFamily.HAZARDS)


@router.get("/marine-features/{family}/{z}/{x}/{y}.geojson")
async def get_marine_features(
    request: Request,
    family: MarineFamily,
    z: Annotated[int, Path(ge=6, le=16)],
    x: Annotated[int, Path(ge=0)],
    y: Annotated[int, Path(ge=0)],
) -> Response:
    # Contours use a fixed, unbuffered Z12 grid at every camera zoom. This
    # preserves source coordinates and identities instead of replacing MVT
    # fragments when the native tile resolution changes.
    if (z > 14 and family != MarineFamily.SOUNDINGS) or family == MarineFamily.PORTS or (
        family == MarineFamily.CONTOURS and z != 12
    ) or (family != MarineFamily.HARBOURS and z < 10):
        raise HTTPException(status_code=422, detail="Unsupported marine snapshot.")
    work = asyncio.create_task(_marine_tile(z, x, y, family, geojson=True))
    try:
        while not work.done():
            if await request.is_disconnected():
                raise HTTPException(status_code=499, detail="Tile request cancelled.")
            await asyncio.wait({work}, timeout=0.1)
        return await work
    finally:
        if not work.done():
            work.cancel()
            with suppress(asyncio.CancelledError):
                await work


async def _marine_tile(z, x, y, family, *, geojson=False):
    try:
        tile = Tile(z, x, y)
    except ValueError as error:
        raise HTTPException(
            status_code=422, detail="Invalid marine XYZ tile."
        ) from error
    try:
        result = await get_marine_service().get_tile(tile, family, **({"geojson": True} if geojson else {}))
    except ProviderUnavailable:
        return _marine_unavailable("Marine data temporarily unavailable.")
    return Response(
        content=result.content,
        media_type="application/geo+json" if geojson else "application/vnd.mapbox-vector-tile",
        headers={
            "Cache-Control": "no-store"
            if family == MarineFamily.SOUNDINGS
            else f"public, max-age={15 if result.failures else 300}",
            "X-NoWave-Marine-Status": "degraded" if result.failures else result.status,
            "X-NoWave-Marine-Sources": ",".join(result.sources),
            "Link": '</api/v1/map/marine-sources>; rel="describedby"',
        },
    )


def _marine_unavailable(message: str) -> JSONResponse:
    # The generic HTTP exception handler drops custom headers. A failure must
    # never look like a complete empty cell or overwrite a useful raster tile.
    return JSONResponse(
        status_code=503,
        content={"error": {"code": "http_503", "message": message, "details": None}},
        headers={
            "Cache-Control": "no-store",
            "X-NoWave-Marine-Status": "unavailable",
            "Retry-After": "15",
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
async def get_bathymetry_tile(
    z: Annotated[int, Path(ge=0, le=14)],
    x: Annotated[int, Path(ge=0)],
    y: Annotated[int, Path(ge=0)],
    request: Request,
) -> Response:
    """Return one visual bathymetry tile in Web Mercator."""

    tile_count = 1 << z

    if x >= tile_count or y >= tile_count:
        raise HTTPException(
            status_code=422,
            detail="Tile coordinates must be within the selected zoom level.",
        )

    if not has_bathymetry_coverage(z, x, y):
        # Old clients and direct requests must never enqueue WMS/coastline work
        # beyond the same published bounds used by the native raster source.
        return Response(
            content=empty_bathymetry_tile(),
            media_type="image/png",
            headers={
                "Cache-Control": "public, max-age=86400",
                "X-NoWave-Marine-Status": "outside-coverage",
            },
        )

    work = asyncio.create_task(
        get_bathymetry_cache(_render_bathymetry_tile).get(Tile(z, x, y))
    )
    try:
        while not work.done():
            if await request.is_disconnected():
                raise HTTPException(status_code=499, detail="Tile request cancelled.")
            await asyncio.wait({work}, timeout=0.1)
        tile = await work
    except (BathymetryUnavailable, ProviderUnavailable, OSError, ValueError) as error:
        logging.getLogger("uvicorn.error.bathymetry").warning(
            "Bathymetry tile=%s/%s/%s failed error=%s detail=%s",
            z, x, y, type(error).__name__, error,
        )
        return _marine_unavailable("Bathymetry temporarily unavailable.")
    finally:
        if not work.done():
            work.cancel()
            with suppress(asyncio.CancelledError):
                await work

    return Response(
        content=tile,
        media_type="image/png",
        headers={
            "Cache-Control": (
                "no-store" if isinstance(tile, UncachedBathymetryTile)
                else "public, max-age=86400"
            ),
            "X-NoWave-Raster-Render": get_bathymetry_cache(_render_bathymetry_tile).VERSION,
            "X-NoWave-Raster-Usage": "visual-only; local-rgb-continuity",
            "Link": '</api/v1/map/marine-sources>; rel="describedby"',
        },
    )


async def _render_bathymetry_tile(tile: Tile) -> bytes:
    raw = await run_in_threadpool(fetch_bathymetry_tile, tile.z, tile.x, tile.y, True)
    if not await run_in_threadpool(has_raster_data, raw):
        return await run_in_threadpool(crop_context, raw)
    mask_started = time.monotonic()
    context = await get_coastline_mask().get_context(tile, raw)
    mask_done = time.monotonic()
    content = await run_in_threadpool(render_visual_water, raw, context.mask)
    logging.getLogger("uvicorn.error.bathymetry").info(
        "Bathymetry tile=%s/%s/%s mask_ms=%.1f visual_ms=%.1f complete=%s",
        tile.z, tile.x, tile.y, (mask_done - mask_started) * 1000,
        (time.monotonic() - mask_done) * 1000, context.complete,
    )
    return content if context.complete else UncachedBathymetryTile(content)
