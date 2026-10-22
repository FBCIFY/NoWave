from io import BytesIO

import httpx
import pytest
from PIL import Image

from app.infrastructure.adapters import emodnet_bathymetry as bathymetry
from app.infrastructure.adapters.emodnet_bathymetry import (
    BathymetryUnavailable,
    fetch_bathymetry_tile,
    recolor_bathymetry_png,
    web_mercator_tile_bbox,
)


def test_world_tile_bbox():
    min_x, min_y, max_x, max_y = web_mercator_tile_bbox(
        0,
        0,
        0,
    )

    assert min_x == pytest.approx(-20037508.342789244)
    assert min_y == pytest.approx(-20037508.342789244)
    assert max_x == pytest.approx(20037508.342789244)
    assert max_y == pytest.approx(20037508.342789244)


def test_zoom_one_north_west_tile_bbox():
    min_x, min_y, max_x, max_y = web_mercator_tile_bbox(
        1,
        0,
        0,
    )

    assert min_x == pytest.approx(-20037508.342789244)
    assert min_y == pytest.approx(0)
    assert max_x == pytest.approx(0)
    assert max_y == pytest.approx(20037508.342789244)


def png_bytes(image):
    output = BytesIO()
    image.save(output, format="PNG")
    return output.getvalue()


def test_recolor_preserves_png_dimensions_and_every_alpha_value():
    source = Image.new("RGBA", (16, 16))
    source.putdata([(249, 245, 7, alpha) for alpha in range(256)])

    content = recolor_bathymetry_png(png_bytes(source))

    assert content.startswith(b"\x89PNG\r\n\x1a\n")
    with Image.open(BytesIO(content)) as result:
        assert result.format == "PNG"
        result.load()
        assert result.size == source.size
        assert result.mode == "RGBA"
        assert result.getchannel("A").tobytes() == source.getchannel("A").tobytes()
        assert result.getpixel((0, 0))[3] == 0
        assert result.getpixel((15, 15))[3] == 255


def test_recolor_preserves_indexed_png_transparency():
    source = Image.new("P", (3, 1))
    source.putpalette([255, 0, 7, 0, 231, 214, 0, 0, 62])
    source.putdata([0, 1, 2])
    source.info["transparency"] = bytes([0, 127, 255])

    result = Image.open(BytesIO(recolor_bathymetry_png(png_bytes(source))))

    assert result.getchannel("A").tobytes() == bytes([0, 127, 255])


# RGB relevés sur la vraie légende EMODnet, du rouge rosé au bleu nuit.
# Les bleus finaux ont presque la même teinte mais des intensités différentes.
EMODNET_COLORS = [
    (255, 96, 101),
    (255, 0, 7),
    (250, 164, 12),
    (249, 245, 7),
    (206, 254, 0),
    (110, 250, 25),
    (31, 243, 149),
    (0, 231, 214),
    (8, 171, 230),
    (8, 92, 238),
    (0, 20, 245),
    (4, 8, 178),
    (1, 1, 94),
    (0, 0, 62),
]


def test_recolor_orders_source_colors_from_light_shallows_to_dark_depths():
    source = Image.new("RGB", (len(EMODNET_COLORS) * 16, 1))
    source.putdata([color for color in EMODNET_COLORS for _ in range(16)])

    result = Image.open(BytesIO(recolor_bathymetry_png(png_bytes(source))))
    colors = [result.getpixel((x * 16 + 8, 0)) for x in range(len(EMODNET_COLORS))]
    luminances = [
        0.2126 * red + 0.7152 * green + 0.0722 * blue
        for red, green, blue, _ in colors
    ]

    assert all(a > b for a, b in zip(luminances, luminances[1:]))
    assert colors[0][:3] == (97, 170, 164)
    assert colors[-1][:3] == (0, 23, 49)
    assert all(red < min(green, blue) and alpha == 255 for red, green, blue, alpha in colors)


def test_recolor_produces_a_continuous_blue_gradient():
    # Sweep the entire observed legend: the deep-blue segment alone spans
    # only five 8-bit colours in the restrained navy palette.
    samples = [
        tuple(round(a + (b - a) * step / 255) for a, b in zip(left, right))
        for (_, left), (_, right) in zip(
            bathymetry._EMODNET_RAMP, bathymetry._EMODNET_RAMP[1:]
        )
        for step in range(256)
    ]
    source = Image.new("RGB", (len(samples), 1))
    source.putdata(samples)
    result = Image.open(BytesIO(recolor_bathymetry_png(png_bytes(source))))
    colors = [result.getpixel((x, 0))[:3] for x in range(result.width)]
    assert len(set(colors)) > 128
    assert all(red < min(green, blue) for red, green, blue in colors)
    assert all(
        all(abs(a - b) <= 1 for a, b in zip(left, right))
        for left, right in zip(colors, colors[1:])
    )
    assert colors[0] == (97, 170, 164)
    assert colors[-1] == (0, 23, 49)


def test_recolor_is_deterministic_across_lut_rebuilds():
    source = Image.new("RGBA", (2, 1))
    source.putdata([(255, 96, 101, 0), (4, 8, 178, 137)])
    content = png_bytes(source)

    first = recolor_bathymetry_png(content)
    bathymetry._blue_color_lut.cache_clear()

    assert recolor_bathymetry_png(content) == first


@pytest.mark.parametrize("content", [b"not a PNG", b"\x89PNG\r\n\x1a\ntruncated"])
def test_recolor_rejects_invalid_png(content):
    with pytest.raises(BathymetryUnavailable, match="Invalid EMODnet PNG"):
        recolor_bathymetry_png(content)


def test_recolor_rejects_non_png_images():
    output = BytesIO()
    Image.new("RGB", (1, 1)).save(output, format="JPEG")

    with pytest.raises(BathymetryUnavailable, match="Expected an EMODnet PNG"):
        recolor_bathymetry_png(output.getvalue())


def test_fetch_caches_the_final_recolored_png(monkeypatch):
    source = png_bytes(Image.new("RGBA", (262, 262), (0, 0, 62, 127)))
    requests = []
    recolor_calls = []

    def request_tile(params):
        requests.append(params)
        return httpx.Response(200, headers={"content-type": "image/png"}, content=source)

    def recolor(content):
        recolor_calls.append(content)
        return recolor_bathymetry_png(content)

    monkeypatch.setattr(bathymetry, "_request_tile", request_tile)
    monkeypatch.setattr(bathymetry, "recolor_bathymetry_png", recolor)
    fetch_bathymetry_tile.cache_clear()
    try:
        first = fetch_bathymetry_tile(8, 131, 94)
        second = fetch_bathymetry_tile(8, 131, 94)
    finally:
        fetch_bathymetry_tile.cache_clear()

    assert first == second
    assert first != source
    assert len(requests) == 1
    assert recolor_calls == [source]
    assert requests[0]["layers"] == "emodnet:mean_multicolour"
    assert requests[0]["srs"] == "EPSG:3857"
    assert requests[0]["transparent"] == "true"
    assert requests[0]["width"] == requests[0]["height"] == "262"
    native = web_mercator_tile_bbox(8, 131, 94)
    padded = list(map(float, requests[0]["bbox"].split(",")))
    assert (padded[2] - padded[0]) / 262 == pytest.approx((native[2] - native[0]) / 256)
    assert Image.open(BytesIO(first)).size == (256, 256)
    result = Image.open(BytesIO(first))
    assert result.getpixel((0, 0))[3] == 127
    assert all(abs(a - b) <= 2 for a, b in zip(result.getpixel((0, 0))[:3], (0, 23, 49)))


def test_smoothing_softens_depth_edges_without_darkening_transparent_coast():
    def tile(transparent_rgb):
        image = Image.new("RGBA", (32, 4), (*transparent_rgb, 0))
        for y in range(4):
            for x in range(16):
                image.putpixel((x, y), (0, 0, 62, 255))
        return Image.open(BytesIO(recolor_bathymetry_png(png_bytes(image))))

    black, white = tile((0, 0, 0)), tile((255, 255, 255))
    # RGB values in the no-data pixels must never tint the adjacent water.
    assert black.getpixel((15, 2)) == white.getpixel((15, 2))
    assert black.getpixel((15, 2))[3] == 255
    assert black.getpixel((16, 2))[3] == 0
    assert all(abs(a - b) <= 2 for a, b in zip(black.getpixel((15, 2))[:3], (0, 23, 49)))

    source = Image.new("RGB", (32, 4), EMODNET_COLORS[0])
    for y in range(4):
        for x in range(16, 32):
            source.putpixel((x, y), EMODNET_COLORS[-1])
    result = Image.open(BytesIO(recolor_bathymetry_png(png_bytes(source))))
    assert result.getpixel((0, 2)) != result.getpixel((15, 2))
    assert result.getpixel((15, 2)) != result.getpixel((16, 2))
    assert result.getpixel((16, 2)) != result.getpixel((31, 2))


def test_feather_only_changes_alpha_inside_known_coverage():
    import numpy as np
    from app.infrastructure.adapters.emodnet_bathymetry import feather_coverage

    source = Image.new("RGBA", (262, 262), (92, 179, 223, 255))
    for x in range(130):
        for y in range(262):
            source.putpixel((x, y), (30, 111, 168, 0))
    before, after = np.array(source), np.array(feather_coverage(source))
    assert np.array_equal(before[:, :, :3], after[:, :, :3])
    assert np.all(after[:, :, 3] <= before[:, :, 3])
    assert np.all(after[:, :130, 3] == 0)
    assert 0 < after[128, 130, 3] < 255
    assert np.all(after[:, 134:, 3] == 255)


def test_feather_adjacent_tiles_share_the_same_global_pixel_lattice():
    import numpy as np
    from app.infrastructure.adapters.emodnet_bathymetry import feather_coverage

    # A coverage edge crosses the tile seam; crop with the production halo.
    big = Image.new("RGBA", (518, 262), (92, 179, 223, 255))
    for x in range(518):
        for y in range(100 + x // 10):
            big.putpixel((x, y), (92, 179, 223, 0))
    full = np.array(feather_coverage(big).crop((3, 3, 515, 259)))
    left = np.array(feather_coverage(big.crop((0, 0, 262, 262))).crop((3, 3, 259, 259)))
    right = np.array(feather_coverage(big.crop((256, 0, 518, 262))).crop((3, 3, 259, 259)))
    assert np.array_equal(full, np.concatenate((left, right), axis=1))
