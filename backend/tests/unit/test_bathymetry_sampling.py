"""Finite-context raster sampling: one WMS request and no XYZ resampling seams."""

from io import BytesIO

import httpx
import numpy as np
import pytest
from PIL import Image

from app.infrastructure.adapters import emodnet_bathymetry as b
from app.infrastructure.marine.visual_water import PADDING


@pytest.mark.parametrize('layout', ['horizontal', 'vertical', 'four-corners'])
@pytest.mark.parametrize('kind', ['constant', 'gradient', 'real-transition', 'no-data', 'partial-alpha'])
def test_wms_contract_and_preprocessing_keep_global_sampling(layout, kind, monkeypatch):
    cols = 1 if layout == 'vertical' else 2
    rows = 1 if layout == 'horizontal' else 2
    width, height = cols * 256 + 2 * PADDING, rows * 256 + 2 * PADDING
    yy, xx = np.indices((height, width))
    data = np.zeros((height, width, 4), dtype=np.uint8)
    if kind == 'real-transition':
        data[:, :, :3] = np.where((xx < 256 + PADDING)[:, :, None], (255, 96, 101), (0, 0, 62))
    elif kind == 'gradient':
        fraction = (xx + yy) / (width + height)
        data[:, :, 0] = 249 - np.rint(96 * fraction).astype(np.uint8)
        data[:, :, 1] = 245
        data[:, :, 2] = 7
    else:
        data[:, :, :3] = (249, 245, 7)
    data[:, :, 3] = 0 if kind == 'no-data' else 255
    if kind == 'partial-alpha':
        data[:, :, 3] = (xx + yy) % 256
    whole = Image.fromarray(data)

    def encode(image):
        output = BytesIO()
        image.save(output, format='PNG')
        return output.getvalue()

    # Expected full render has no tile boundaries; each tile must match it.
    def wms_encode(image):
        # Match the associated-RGB convention observed in the bilinear WMS.
        premultiplied = image.convert('RGBa')
        return encode(Image.frombytes('RGBA', image.size, premultiplied.tobytes()))

    expected = b.feather_coverage(Image.open(BytesIO(b.recolor_bathymetry_png(wms_encode(whole), associated_alpha=True))).convert('RGBA'))
    expected = np.array(expected.crop((PADDING, PADDING, width - PADDING, height - PADDING)))
    requests = []
    start = b.web_mercator_tile_bbox(14, 8461, 6013)
    pixel = (start[2] - start[0]) / 256

    def request(params):
        assert params['interpolations'] == 'bilinear'
        assert params['width'] == params['height'] == str(256 + 2 * PADDING)
        bbox = list(map(float, params['bbox'].split(',')))
        # Sample pitch stays unchanged; expanded borders must not stretch data.
        assert (bbox[2] - bbox[0]) / (256 + 2 * PADDING) == pytest.approx(pixel)
        col = round((bbox[0] + PADDING * pixel - start[0]) / (256 * pixel))
        row = round((start[3] - bbox[3] + PADDING * pixel) / (256 * pixel))
        patch = whole.crop((col * 256, row * 256, col * 256 + 256 + 2 * PADDING, row * 256 + 256 + 2 * PADDING))
        requests.append((col, row))
        return httpx.Response(200, headers={'content-type': 'image/png'}, content=wms_encode(patch))

    monkeypatch.setattr(b, '_request_tile', request)
    b.fetch_bathymetry_tile.cache_clear()
    actual = np.zeros_like(expected)
    try:
        for row in range(rows):
            for col in range(cols):
                png = b.fetch_bathymetry_tile(14, 8461 + col, 6013 + row)
                assert b.fetch_bathymetry_tile(14, 8461 + col, 6013 + row) == png
                actual[row * 256:(row + 1) * 256, col * 256:(col + 1) * 256] = np.array(Image.open(BytesIO(png)))
    finally:
        b.fetch_bathymetry_tile.cache_clear()
    assert len(requests) == rows * cols  # No extra upstream request on overzoom/reuse.
    assert np.array_equal(actual, expected)
    original_alpha = data[PADDING:height - PADDING, PADDING:width - PADDING, 3]
    assert np.all(actual[:, :, 3] <= original_alpha)
    assert np.all(actual[:, :, 3][original_alpha == 0] == 0)
    # Existing subpixel smoothing cannot erase a real broad transition.
    if kind == 'real-transition' and cols == 2:
        assert not np.array_equal(actual[100, 240, :3], actual[100, 270, :3])


@pytest.mark.parametrize('zoom', [13.8, 15, 16, 16.3])
def test_fractional_overzoom_is_display_sampling_only_and_preserves_unknown_interiors(zoom):
    raw = Image.new('RGBA', (256, 256), (40, 140, 160, 255))
    raw.paste((40, 140, 160, 0), (80, 80, 120, 120))
    scale = 2 ** (zoom - 13)
    sampled = raw.resize((round(256 * scale), round(256 * scale)), Image.Resampling.BILINEAR)
    assert sampled.getpixel((round(100 * scale), round(100 * scale)))[3] == 0
    assert sampled.getpixel((round(20 * scale), round(20 * scale))) == (40, 140, 160, 255)


@pytest.mark.parametrize('offset', [(128, 0), (0, 128), (128, 128)])
def test_combined_preprocessing_and_reconstruction_are_independent_of_xyz_cut(offset):
    from app.infrastructure.marine.visual_water import RADIUS, render_visual_water

    assert PADDING >= RADIUS + 3  # Reconstruction support + inherited filters.
    dim = 256 + 2 * PADDING
    yy, xx = np.indices((dim + 128, dim + 128))
    pixels = np.zeros((dim + 128, dim + 128, 4), dtype=np.uint8)
    pixels[:, :, :3] = np.where(((xx + yy) % 63 < 32)[:, :, None], (255, 96, 101), (0, 0, 62))
    pixels[:, :, 3] = np.where(((xx % 31 < 5) | (yy % 37 < 4)), 0, 255)
    canvas = Image.fromarray(pixels)

    def render(x, y):
        patch = canvas.crop((x, y, x + dim, y + dim))
        associated = patch.convert('RGBa')
        upstream = Image.frombytes('RGBA', patch.size, associated.tobytes())
        buf = BytesIO()
        upstream.save(buf, format='PNG')
        recolored = Image.open(BytesIO(b.recolor_bathymetry_png(buf.getvalue(), associated_alpha=True)))
        padded = b.feather_coverage(recolored.convert('RGBA'))
        buf = BytesIO()
        padded.save(buf, format='PNG')
        return np.array(Image.open(BytesIO(render_visual_water(buf.getvalue(), Image.new('L', (dim, dim), 255)))))

    first, shifted = render(0, 0), render(*offset)
    x, y = offset
    assert np.array_equal(first[y:256, x:256], shifted[:256-y, :256-x])
