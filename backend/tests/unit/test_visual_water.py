"""Display-only coastal continuity, known geometry and exact source coverage."""

import asyncio
import base64
from io import BytesIO

import mapbox_vector_tile
import numpy as np
import pytest
from PIL import Image
from shapely.geometry import box, mapping

from app.domain.marine_tile import Tile
from app.infrastructure.marine.coastline import CoastlineMask, rasterize_ocean
from app.infrastructure.marine.visual_water import (
    PADDING, SIZE, context_neighbours, crop_context, render_visual_water,
)

DIM = SIZE + 2 * PADDING


def png(image):
    output = BytesIO()
    image.save(output, format="PNG")
    return output.getvalue()


def source(colour=(40, 140, 160), alpha=255):
    return Image.new("RGBA", (DIM, DIM), (*colour, alpha))


def image(content):
    result = Image.open(BytesIO(content))
    result.load()
    return result


def source_coverage(rendered):
    saved = rendered.info.get("NoWave.SourceCoverage")
    if saved is None:
        return np.array(rendered.getchannel("A"))
    return np.frombuffer(base64.b64decode(saved), dtype=np.uint8).reshape(SIZE, SIZE)


@pytest.mark.parametrize("colour", [(97, 170, 164), (0, 45, 81)])
def test_missing_water_uses_original_neighbour_colour_without_inventing_coverage(colour):
    raw = source(colour)
    raw.paste((255, 255, 255, 0), (PADDING + 112, PADDING + 112, PADDING + 117, PADDING + 117))
    result = image(render_visual_water(png(raw), Image.new("L", (DIM, DIM), 255)))
    assert result.getpixel((114, 114)) == (*colour, 255)
    assert result.getpixel((50, 50)) == (*colour, 255)
    assert source_coverage(result)[114, 114] == 0
    assert result.info["NoWave.VisualFillPixels"] == '25'
    assert 'no added depth' in result.info['NoWave.VisualUse']


@pytest.mark.parametrize("kind", ['quay', 'long-dyke', 'legitimate-gray-land'])
def test_confirmed_structures_neither_receive_nor_donate_colour(kind):
    raw = source()
    mask = Image.new("L", (DIM, DIM), 255)
    # A grey structure, with deliberately opaque pixels, beside missing water.
    raw.paste((180, 180, 180, 255), (PADDING + 120, 0, PADDING + 132, DIM))
    mask.paste(0, (PADDING + 120, 0, PADDING + 132, DIM))
    raw.paste((255, 255, 255, 0), (PADDING + 115, PADDING + 92, PADDING + 120, PADDING + 132))
    result = image(render_visual_water(png(raw), mask))
    assert result.getpixel((118, 112)) == (40, 140, 160, 255)
    assert result.getpixel((125, 112))[3] == 0
    assert source_coverage(result)[112, 125] == 0


def test_large_holes_and_missing_tiles_abstain_instead_of_propagating_filled_colours():
    raw = source(alpha=0)
    water = Image.new("L", (DIM, DIM), 255)
    result = image(render_visual_water(png(raw), water))
    assert result.getchannel('A').getbbox() is None
    raw.paste((40, 140, 160, 255), (0, 0, PADDING + 112, DIM))
    result = image(render_visual_water(png(raw), water))
    assert result.getpixel((114, 100))[3] == 255  # Bounded nearby visual repair.
    assert result.getpixel((150, 100))[3] == 0   # Never an iterative flood fill.
    assert source_coverage(result)[100, 114] == 0


def test_seven_donors_are_insufficient():
    raw = source(alpha=0)
    for x in range(7):
        raw.putpixel((120 + x, 120), (40, 140, 160, 255))
    result = image(render_visual_water(png(raw), Image.new("L", (DIM, DIM), 255)))
    assert result.info['NoWave.VisualFillPixels'] == '0'
    assert result.getpixel((114, 114))[3] == 0


def test_partial_alpha_uses_local_rgb_but_retains_exact_provider_coverage():
    raw = source()
    raw.putpixel((PADDING + 112, PADDING + 112), (40, 140, 160, 137))
    result = image(render_visual_water(png(raw), Image.new("L", (DIM, DIM), 255)))
    assert result.getpixel((112, 112)) == (40, 140, 160, 255)
    assert source_coverage(result)[112, 112] == 137


def test_land_mask_keeps_the_entire_tile_transparent():
    result = image(render_visual_water(png(source()), Image.new("L", (DIM, DIM), 0)))
    assert result.getchannel('A').getbbox() is None
    assert result.info['NoWave.VisualFillPixels'] == '0'


@pytest.mark.parametrize('axis', ['horizontal', 'vertical', 'four-corners'])
def test_gradients_and_visual_repairs_share_a_lattice_across_tile_edges(axis):
    # Global source includes a real halo; every tile samples the same pixels.
    h = 2 * SIZE + 2 * PADDING
    yy, xx = np.indices((h, h))
    source_array = np.zeros((h, h, 4), dtype=np.uint8)
    source_array[:, :, 0] = 20
    source_array[:, :, 1] = 60 + (xx + yy) // 8
    source_array[:, :, 2] = 160
    source_array[:, :, 3] = 255
    join = SIZE + PADDING
    if axis == 'horizontal':
        source_array[:, join - 2:join + 2, 3] = 0
    elif axis == 'vertical':
        source_array[join - 2:join + 2, :, 3] = 0
    else:
        source_array[join - 2:join + 2, join - 2:join + 2, 3] = 0
    final = np.zeros((2 * SIZE, 2 * SIZE, 4), dtype=np.uint8)
    coverage = np.zeros((2 * SIZE, 2 * SIZE), dtype=np.uint8)
    for row in range(2):
        for col in range(2):
            patch = source_array[row * SIZE:row * SIZE + DIM, col * SIZE:col * SIZE + DIM]
            result = image(render_visual_water(png(Image.fromarray(patch)), Image.new('L', (DIM, DIM), 255)))
            final[row * SIZE:(row + 1) * SIZE, col * SIZE:(col + 1) * SIZE] = np.array(result)
            coverage[row * SIZE:(row + 1) * SIZE, col * SIZE:(col + 1) * SIZE] = source_coverage(result)
    original = source_array[PADDING:-PADDING, PADDING:-PADDING]
    assert np.array_equal(coverage, original[:, :, 3])
    assert np.all(final[:, :, 3] == 255)
    assert np.max(np.abs(final[:, :, 1].astype(int) - original[:, :, 1].astype(int))) <= 1
    assert np.array_equal(final[original[:, :, 3] == 255], original[original[:, :, 3] == 255])


def test_context_only_fetches_neighbours_when_repair_support_crosses_an_edge():
    raw = source()
    mask = png(Image.new('L', (256, 256), 255))
    assert context_neighbours(png(raw), mask) == []
    raw.putpixel((PADDING, PADDING + 100), (255, 255, 255, 0))
    assert context_neighbours(png(raw), mask) == [(-1, 0)]
    assert image(crop_context(png(raw))).size == (256, 256)


def test_osm_pier_polygons_are_protected_even_when_the_ocean_contains_them():
    content = mapbox_vector_tile.encode([
        {'name': 'ocean', 'features': [{'geometry': mapping(box(0, 0, 4096, 4096)), 'properties': {}}]},
        {'name': 'pier_polygons', 'features': [{'geometry': mapping(box(2000, 0, 2200, 3000)), 'properties': {'kind': 'pier'}}]},
    ])
    mask = image(rasterize_ocean(content))
    assert mask.getpixel((131, 140)) == 0
    assert mask.getpixel((100, 140)) == 255


def test_neighbour_masks_reuse_the_existing_persistent_osm_cache():
    async def run():
        class HTTP:
            calls = 0

            async def get(self, url, **options):
                self.calls += 1
                assert options['osm'] and options['ttl'] >= 604800
                return mapbox_vector_tile.encode({'name': 'ocean', 'features': [
                    {'geometry': mapping(box(0, 0, 4096, 4096)), 'properties': {}}
                ]})

        http = HTTP()
        coast = CoastlineMask(http)
        raw = source()
        raw.putpixel((PADDING, PADDING + 100), (0, 0, 0, 0))
        first = await coast.get_context(Tile(14, 8462, 6014), png(raw))
        second = await coast.get_context(Tile(14, 8462, 6014), png(raw))
        assert first.tobytes() == second.tobytes()
        assert http.calls == 2  # Central mask and one western neighbour, not nine.
        assert first.getpixel((0, 100)) == 255
    asyncio.run(run())
