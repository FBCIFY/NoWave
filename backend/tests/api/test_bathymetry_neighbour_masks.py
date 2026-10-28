"""Real coastal composition and cache recovery when optional OSM masks fail."""

from collections import Counter
import asyncio
from io import BytesIO
import sqlite3
from types import SimpleNamespace

import mapbox_vector_tile
import numpy as np
import pytest
from fastapi.testclient import TestClient
from PIL import Image
from shapely.geometry import box, mapping

from app.domain.marine import ProviderUnavailable
from app.domain.marine_tile import Tile
from app.infrastructure.marine.bathymetry_cache import BathymetryTileCache
from app.infrastructure.marine.coastline import CoastlineMask, rasterize_ocean
from app.infrastructure.marine.visual_water import PADDING, SIZE, render_visual_water
from app.main import app


CENTRE = Tile(14, 8462, 6014)
WEST = Tile(14, 8461, 6014)
URL = "/api/v1/map/bathymetry/14/8462/6014.png?v=marine-visual-7"
DIM = SIZE + 2 * PADDING


def png(image):
    output = BytesIO()
    image.save(output, format="PNG")
    return output.getvalue()


@pytest.fixture
def coastal_pipeline(tmp_path, monkeypatch):
    # Published water with a real land/structure exclusion, even with an opaque
    # supplier raster. Neighbouring geometry is never inferred from the centre.
    geometry = mapbox_vector_tile.encode(
        [
            {
                "name": "ocean",
                "features": [
                    {"geometry": mapping(box(0, 0, 4096, 4096)), "properties": {}}
                ],
            },
            {
                "name": "pier_polygons",
                "features": [
                    {"geometry": mapping(box(1536, 1536, 2048, 2048)), "properties": {}}
                ],
            },
        ]
    )
    raw = Image.new("RGBA", (DIM, DIM), (40, 140, 160, 255))
    raw.paste((80, 180, 200, 255), (0, 0, PADDING, DIM))
    raw.paste((0, 0, 0, 0), (PADDING, 100, PADDING + 5, 110))
    state = SimpleNamespace(
        failed={WEST},
        calls=Counter(),
        fetches=0,
        raw=raw,
        geometry=geometry,
    )

    class HTTP:
        async def get(self, url, **options):
            tile = Tile(*map(int, url.removesuffix(".mvt").split("/")[-3:]))
            state.calls[tile] += 1
            assert options == {"ttl": 604800, "osm": True, "vector_tile": True}
            if tile in state.failed:
                raise ProviderUnavailable("optional coastline offline")
            return geometry

    state.coast = CoastlineMask(HTTP())
    state.path = tmp_path / "bathymetry.sqlite3"
    state.cache = None

    def fetch(z, x, y, padded):
        assert (z, x, y, padded) == (14, 8462, 6014, True)
        state.fetches += 1
        return png(state.raw)

    def get_cache(render):
        if state.cache is None:
            state.cache = BathymetryTileCache(render, state.path)
        return state.cache

    monkeypatch.setattr("app.api.routes.map_tiles.fetch_bathymetry_tile", fetch)
    monkeypatch.setattr(
        "app.api.routes.map_tiles.get_coastline_mask", lambda: state.coast
    )
    monkeypatch.setattr("app.api.routes.map_tiles.get_bathymetry_cache", get_cache)
    return state


def expected_render(state, *, west_available):
    mask = Image.open(BytesIO(rasterize_ocean(state.geometry)))
    context = Image.new("L", (DIM, DIM), 0)
    context.paste(mask, (PADDING, PADDING))
    if west_available:
        context.paste(mask, (PADDING - SIZE, PADDING))
    return render_visual_water(png(state.raw), context)


def test_west_mask_failure_keeps_central_raster_200_without_daily_caching(
    coastal_pipeline,
):
    state = coastal_pipeline
    with TestClient(app) as client:
        response = client.get(URL)
    assert response.status_code == 200
    assert response.content == expected_render(state, west_available=False)
    assert response.headers["cache-control"] == "no-store"
    assert response.headers["x-nowave-raster-render"] == "marine-visual-7"
    assert state.calls == {CENTRE: 1, WEST: 1}
    assert not state.cache._memory
    with sqlite3.connect(state.path) as db:
        assert db.execute("SELECT COUNT(*) FROM tiles").fetchone()[0] == 0


def test_central_mask_failure_is_non_cacheable_503(coastal_pipeline):
    state = coastal_pipeline
    state.failed = {CENTRE}
    with TestClient(app) as client:
        response = client.get(URL)
    assert response.status_code == 503
    assert response.headers['cache-control'] == 'no-store'
    assert response.headers['x-nowave-marine-status'] == 'unavailable'
    assert response.json()['error']['code'] == 'http_503'
    assert state.calls == {CENTRE: 1}
    assert not state.cache._memory


def test_all_eight_neighbours_unavailable_keep_valid_central_raster(coastal_pipeline):
    state = coastal_pipeline
    neighbours = {
        Tile(14, CENTRE.x + dx, CENTRE.y + dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1)
    } - {CENTRE}
    state.failed = neighbours
    for x in (PADDING, PADDING + SIZE - 1):
        for y in (PADDING, PADDING + SIZE - 1):
            state.raw.putpixel((x, y), (0, 0, 0, 0))
    with TestClient(app) as client:
        response = client.get(URL)
    assert response.status_code == 200
    assert response.headers["cache-control"] == "no-store"
    assert response.content == expected_render(state, west_available=False)
    assert state.calls == {tile: 1 for tile in neighbours | {CENTRE}}
    assert not state.cache._memory


def test_api_does_not_translate_neighbour_cancellation_into_200_or_503(
    coastal_pipeline, monkeypatch
):
    from app.api.routes.map_tiles import get_bathymetry_tile

    state = coastal_pipeline
    original = state.coast.get_mask

    async def get_mask(tile):
        if tile == WEST:
            raise asyncio.CancelledError()
        return await original(tile)

    monkeypatch.setattr(state.coast, "get_mask", get_mask)

    async def scenario():
        async def connected():
            return False
        with pytest.raises(asyncio.CancelledError):
            await get_bathymetry_tile(
                CENTRE.z, CENTRE.x, CENTRE.y, SimpleNamespace(is_disconnected=connected)
            )
        assert not state.cache._memory
        await state.cache.close()

    asyncio.run(scenario())


def test_available_neighbour_keeps_normal_pixels_and_daily_cache(coastal_pipeline):
    state = coastal_pipeline
    state.failed.clear()
    with TestClient(app) as client:
        first, second = client.get(URL), client.get(URL)
    assert first.status_code == second.status_code == 200
    assert (
        first.content == second.content == expected_render(state, west_available=True)
    )
    assert first.headers["cache-control"] == "public, max-age=86400"
    assert state.calls == {CENTRE: 1, WEST: 1}
    assert state.fetches == 1
    assert state.cache.metrics["memory_hits"] == 1


@pytest.mark.parametrize("restart", [False, True])
def test_recovered_neighbour_renders_again_immediately_then_caches(
    coastal_pipeline, restart
):
    state = coastal_pipeline
    with TestClient(app) as client:
        degraded = client.get(URL)
        assert degraded.status_code == 200
        assert degraded.headers["cache-control"] == "no-store"
        if restart:
            # Recreate the raster cache against the same SQLite file. An
            # incomplete result must not survive in RAM or on disk.
            state.cache = None
        state.failed.clear()
        recovered = client.get(URL)
        repeated = client.get(URL)
    assert recovered.status_code == repeated.status_code == 200
    assert recovered.headers["cache-control"] == "public, max-age=86400"
    assert (
        recovered.content
        == repeated.content
        == expected_render(state, west_available=True)
    )
    assert recovered.content != degraded.content
    assert state.fetches == 2
    assert state.calls == {CENTRE: 1, WEST: 2}
    with sqlite3.connect(state.path) as db:
        rows = db.execute("SELECT content FROM tiles").fetchall()
    assert rows == [(recovered.content,)]


def test_missing_neighbour_cannot_extend_marine_coverage_or_paint_a_pier(
    coastal_pipeline,
):
    state = coastal_pipeline
    with TestClient(app) as client:
        response = client.get(URL)
    assert response.status_code == 200
    actual = Image.open(BytesIO(response.content))
    water = np.array(Image.open(BytesIO(rasterize_ocean(state.geometry))))
    alpha = np.array(actual.getchannel("A"))
    assert np.all(alpha <= water)
    assert alpha[144, 110] == 0  # Published pier, inside opaque source pixels.
    assert actual.getpixel((128, 40)) == (40, 140, 160, 255)
