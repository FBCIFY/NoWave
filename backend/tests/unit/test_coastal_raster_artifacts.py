"""No-data remains unknown around coastlines, even when display tiles overzoom.

The frontend fixes only the backdrop. These offline production-pipeline tests
protect against 'fixing' the visual gap by manufacturing raster coverage.
"""

from io import BytesIO

import mapbox_vector_tile
import numpy as np
import pytest
from PIL import Image
from shapely import contains_xy
from shapely.affinity import translate
from shapely.geometry import MultiPolygon, Polygon, box, mapping

from app.infrastructure.adapters.emodnet_bathymetry import (
    feather_coverage,
    recolor_bathymetry_png,
)
from app.infrastructure.marine.coastline import apply_ocean_mask, rasterize_ocean


def png(image):
    output = BytesIO()
    image.save(output, format="PNG")
    return output.getvalue()


def vector(water):
    return mapbox_vector_tile.encode(
        {"name": "ocean", "features": [{"geometry": mapping(water), "properties": {}}]},
        default_options={"extents": 256},
    )


def rgba(content):
    return Image.open(BytesIO(content)).convert("RGBA")


def pipeline(source, water):
    recolored = rgba(recolor_bathymetry_png(png(source)))
    cropped = feather_coverage(recolored).crop((3, 3, 259, 259))
    mask = rasterize_ocean(vector(water))
    return cropped, rgba(apply_ocean_mask(png(cropped), mask))


@pytest.mark.parametrize(
    "water",
    [
        pytest.param(box(-8, -8, 127.75, 264), id="classic-coast-partial-pixel"),
        pytest.param(box(-8, -8, 176, 264), id="straight-quay"),
        pytest.param(
            box(-8, -8, 220, 264).difference(box(110, 124, 264, 132)),
            id="narrow-jetty",
        ),
        pytest.param(
            box(-8, -8, 264, 264).difference(
                box(160, 60, 240, 220).difference(box(160, 80, 220, 200))
            ),
            id="harbour-basin-with-entrance",
        ),
        pytest.param(
            Polygon(
                [(-8, -8), (264, -8), (264, 264), (-8, 264)],
                holes=[[(160, 80), (220, 80), (220, 160), (160, 160)]],
            ),
            id="island-hole",
        ),
        pytest.param(
            MultiPolygon([box(-8, -8, 100, 264), box(120, -8, 264, 264)]),
            id="separate-water-polygons",
        ),
        pytest.param(box(-8, -8, 264, 264), id="fully-opaque-water-mask"),
        pytest.param(box(300, 300, 320, 320), id="fully-transparent-land-mask"),
    ],
)
def test_real_pipeline_never_extends_provider_coverage_or_paints_land(water):
    source = Image.new("RGBA", (262, 262), (249, 245, 7, 255))
    # A real no-data hole in water, plus partially covered provider pixels.
    source.paste((255, 255, 255, 0), (53, 73, 69, 89))
    source.paste((249, 245, 7, 137), (83, 103, 91, 111))
    before, final = pipeline(source, water)
    a = np.array(source.crop((3, 3, 259, 259)))[:, :, 3]
    pre = np.array(before)
    result = np.array(final)
    ys, xs = np.indices((256, 256))
    inside = contains_xy(water, xs + 0.5, 255.5 - ys)
    assert np.all(result[:, :, 3] <= pre[:, :, 3])
    assert np.all(pre[:, :, 3] <= a)
    assert np.all(result[:, :, 3][~inside] == 0)
    assert np.all(result[:, :, 3][a == 0] == 0)
    assert np.array_equal(result[:, :, :3], pre[:, :, :3])
    # The OSM mask may remove colour on land, never restore missing data.
    if inside[77, 55]:
        assert result[77, 55, 3] == 0
    if inside[105, 85]:
        assert 0 < result[105, 85, 3] <= 137


def test_entirely_missing_bathymetry_stays_transparent_even_in_open_water():
    source = Image.new("RGBA", (262, 262), (249, 245, 7, 0))
    before, final = pipeline(source, box(-8, -8, 264, 264))
    assert before.getchannel("A").getbbox() is None
    assert final.getchannel("A").getbbox() is None


def test_four_xyz_corners_use_one_pixel_lattice_and_keep_a_crossing_island():
    water = Polygon(
        [(-8, -8), (520, -8), (520, 520), (-8, 520)],
        holes=[[(245, 245), (267, 245), (267, 267), (245, 267)]],
    )
    alpha = np.zeros((512, 512), dtype=np.uint8)
    for row in range(2):
        for col in range(2):
            local = translate(water, xoff=-col * 256, yoff=-row * 256)
            # MVT geometry uses a bottom-left origin, NumPy a top-left one.
            mask = np.array(Image.open(BytesIO(rasterize_ocean(vector(local)))))
            alpha[(1 - row) * 256:(2 - row) * 256, col * 256:(col + 1) * 256] = mask
    ys, xs = np.indices((512, 512))
    expected = contains_xy(water, xs + 0.5, 511.5 - ys)
    assert np.array_equal(alpha > 0, expected)
    # Outside the island neither the two-tile seams nor four-tile join erode water.
    assert np.all(alpha[100, 254:258] == 255)
    assert np.all(alpha[254:258, 100] == 255)
    assert np.all(alpha[254:258, 254:258] == 0)


@pytest.mark.parametrize("factor", [2, 4], ids=["z14-to-z15", "z14-to-z16"])
def test_overzoom_cannot_turn_unknown_or_land_interiors_into_depth(factor):
    source = Image.new("RGBA", (262, 262), (249, 245, 7, 255))
    source.paste((249, 245, 7, 0), (53, 73, 69, 89))
    _, tile = pipeline(source, box(-8, -8, 160, 264))
    # This models sampling only. Real Mapbox overzoom is verified on Android.
    sampled = tile.resize((256 * factor, 256 * factor), Image.Resampling.BILINEAR)
    assert sampled.getpixel((58 * factor, 78 * factor))[3] == 0
    assert sampled.getpixel((220 * factor, 100 * factor))[3] == 0
    assert sampled.getpixel((20 * factor, 20 * factor))[3] == 255
