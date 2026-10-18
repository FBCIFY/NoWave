"""Mixed real coastlines and geometric regressions, with no live downloads."""

import asyncio
import json
from io import BytesIO
from pathlib import Path

import mapbox_vector_tile
import pytest
from google.protobuf.message import DecodeError
from PIL import Image
from shapely.geometry import Polygon, box, mapping

from app.domain.marine import ProviderUnavailable
from app.domain.marine_tile import Tile
from app.infrastructure.marine.coastline import (
    CoastlineMask,
    apply_ocean_mask,
    rasterize_ocean,
    has_raster_data,
)

REAL = json.loads(
    (Path(__file__).parents[1] / "fixtures/marine/coastline-real.json").read_text()
)


def vector(geometry, extent=4096):
    return mapbox_vector_tile.encode(
        {
            "name": "ocean",
            "features": [{"geometry": mapping(geometry), "properties": {}}],
        },
        default_options={"extents": extent},
    )


def rgba(alpha=255):
    image = Image.new("RGBA", (256, 256), (92, 179, 223, alpha))
    out = BytesIO()
    image.save(out, format="PNG")
    return out.getvalue()


def image(content):
    return Image.open(BytesIO(content))


@pytest.mark.parametrize(
    "key,land,sea",
    [
        ("6/33/23", (141, 42), (200, 200)),
        ("9/264/187", (7, 196), (128, 245)),
        ("12/2116/1503", (14, 104), (128, 245)),
    ],
)
def test_real_osm_coast_z6_z9_z12_rejects_land_and_keeps_water(key, land, sea):
    data = REAL[key]
    content = mapbox_vector_tile.encode(
        {"name": "ocean", "features": data["features"]},
        default_options={"extents": data["extent"]},
    )
    result = image(apply_ocean_mask(rgba(), rasterize_ocean(content)))
    assert result.getpixel(land)[3] == 0
    assert result.getpixel(sea) == (92, 179, 223, 255)


def test_island_holes_and_nonstandard_extent_are_retained():
    water = Polygon(
        [(0, 0), (8192, 0), (8192, 8192), (0, 8192)],
        holes=[[(2048, 2048), (6144, 2048), (6144, 6144), (2048, 6144)]],
    )
    mask = image(rasterize_ocean(vector(water, 8192)))
    assert mask.getpixel((128, 128)) == 0
    assert mask.getpixel((20, 128)) == 255


def test_adjacent_tiles_keep_continuous_water_without_eroding_tile_edges():
    west = image(rasterize_ocean(vector(box(-128, -128, 4224, 4096))))
    east = image(rasterize_ocean(vector(box(-128, -128, 4224, 4096))))
    assert [west.getpixel((255, y)) for y in range(256)] == [255] * 256
    assert [east.getpixel((0, y)) for y in range(256)] == [255] * 256


def test_antialiasing_stays_on_water_and_cannot_add_source_alpha():
    mask = rasterize_ocean(vector(box(0, 0, 2044, 4096)))
    result = image(apply_ocean_mask(rgba(137), mask))
    assert result.getpixel((126, 100)) == (92, 179, 223, 137)
    assert 0 < result.getpixel((127, 100))[3] < 137
    assert result.getpixel((128, 100))[3] == 0
    assert image(apply_ocean_mask(rgba(0), mask)).getchannel("A").getbbox() is None


def test_inland_water_does_not_become_ocean_but_published_dock_is_water():
    features = [
        {"geometry": mapping(box(0, 0, 2048, 4096)), "properties": {"kind": "dock"}},
        {
            "geometry": mapping(box(2048, 0, 4096, 4096)),
            "properties": {"kind": "glacier"},
        },
    ]
    mask = image(
        rasterize_ocean(
            mapbox_vector_tile.encode({"name": "water_polygons", "features": features})
        )
    )
    assert mask.getpixel((64, 100)) == 255
    assert mask.getpixel((192, 100)) == 0


@pytest.mark.parametrize("body", [b"", b"not a vector tile"])
def test_absent_or_corrupt_geometry_never_returns_an_unmasked_success(body):
    with pytest.raises((ProviderUnavailable, DecodeError)):
        rasterize_ocean(body)


def test_cache_single_flight_and_osm_policy_are_preserved():
    class HTTP:
        calls = 0

        async def get(self, url, **kwargs):
            self.calls += 1
            assert kwargs == {"ttl": 604800, "osm": True, "vector_tile": True}
            return vector(box(0, 0, 4096, 4096))

    async def run():
        http = HTTP()
        coast = CoastlineMask(http)
        results = await asyncio.gather(
            *(coast.get_mask(Tile(6, 33, 23)) for _ in range(3))
        )
        assert len(set(results)) == 1 and http.calls == 1
        assert coast._bytes == len(results[0])

    asyncio.run(run())


def test_failure_is_retryable_and_not_cached_as_empty_land():
    class HTTP:
        calls = 0

        async def get(self, *args, **kwargs):
            self.calls += 1
            if self.calls == 1:
                raise ProviderUnavailable("offline")
            return vector(box(0, 0, 4096, 4096))

    async def run():
        http = HTTP()
        coast = CoastlineMask(http)
        with pytest.raises(ProviderUnavailable):
            await coast.get_mask(Tile(9, 264, 187))
        assert not coast._cache
        assert (
            image(await coast.get_mask(Tile(9, 264, 187))).getpixel((128, 128)) == 255
        )
        assert http.calls == 2

    asyncio.run(run())


def test_expired_mask_can_be_evicted_while_its_refresh_is_in_flight():
    async def run():
        refreshing = asyncio.Event()
        release = asyncio.Event()
        content = vector(box(0, 0, 4096, 4096))
        mask = rasterize_ocean(content)
        target = Tile(10, 0, 375)

        class HTTP:
            async def get(self, url, **kwargs):
                if url.endswith('/10/0/375.mvt'):
                    refreshing.set()
                    await release.wait()
                return content

        coast = CoastlineMask(HTTP())
        # A full cache, with the expired target as the oldest entry.
        for x in range(512):
            coast._cache[Tile(10, x, 375)] = (0 if x == 0 else float('inf'), mask)
        coast._bytes = len(mask) * 512
        pending = asyncio.create_task(coast.get_mask(target))
        await refreshing.wait()
        await coast.get_mask(Tile(10, 512, 375))
        assert target not in coast._cache
        release.set()
        assert await pending == mask
        assert len(coast._cache) == 512
        assert coast._bytes == sum(len(v[1]) for v in coast._cache.values())

    asyncio.run(run())


def test_transparent_nodata_is_detected_without_treating_shallow_water_as_land():
    assert not has_raster_data(rgba(0))
    assert has_raster_data(rgba(1))


def test_island_crossing_a_tile_boundary_remains_land_on_both_sides():
    from shapely.affinity import translate

    water = Polygon(
        [(-128, -128), (8320, -128), (8320, 4224), (-128, 4224)],
        holes=[[(3904, 1500), (4288, 1500), (4288, 2500), (3904, 2500)]],
    )
    west = image(rasterize_ocean(vector(water)))
    east = image(rasterize_ocean(vector(translate(water, xoff=-4096))))
    for y in [10, 245]:
        assert west.getpixel((255, y)) == east.getpixel((0, y)) == 255
    assert west.getpixel((255, 128)) == east.getpixel((0, 128)) == 0
