"""Bounded RGB continuity for display, separate from source depth coverage.

Only original, fully covered water pixels donate colour. Reconstructed pixels
never become donors. No numerical depth is read, generated or modified here.
"""

import base64
from io import BytesIO

import numpy as np
from PIL import Image, PngImagePlugin

SIZE = 256
# Reconstruction uses 8 pixels; source RGB/alpha preprocessing needs 3 more.
# Keep the WMS halo independent of the reconstruction radius to prevent seams.
RADIUS = 8
PADDING = 12
MIN_DONORS = 8
MIN_SUPPORT = 0.05


def _rgba(content):
    with Image.open(BytesIO(content)) as image:
        if image.size != (SIZE + 2 * PADDING, SIZE + 2 * PADDING):
            raise ValueError("Unexpected visual raster context dimensions")
        return image.convert("RGBA")


def crop_context(content):
    image = _rgba(content).crop((PADDING, PADDING, PADDING + SIZE, PADDING + SIZE))
    output = BytesIO()
    image.save(output, format="PNG")
    return output.getvalue()


def context_neighbours(content, mask):
    """Only request OSM neighbours needed by a potential boundary repair."""
    alpha = np.array(_rgba(content).getchannel("A"))[
        PADDING:PADDING + SIZE, PADDING:PADDING + SIZE
    ]
    with Image.open(BytesIO(mask)) as image:
        water = np.array(image.convert("L"))
    candidates = (alpha < 255) & (water > 0)
    result = []
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            if dx == dy == 0:
                continue
            ys = slice(0, RADIUS) if dy < 0 else slice(-RADIUS, None) if dy > 0 else slice(None)
            xs = slice(0, RADIUS) if dx < 0 else slice(-RADIUS, None) if dx > 0 else slice(None)
            if candidates[ys, xs].any():
                result.append((dx, dy))
    return result


def _box_sum(values, radius):
    """Finite-support sums on one global pixel lattice, no edge replication."""
    pads = [(radius, radius), (radius, radius)] + [(0, 0)] * (values.ndim - 2)
    padded = np.pad(values, pads)
    leading = [(1, 0), (1, 0)] + [(0, 0)] * (values.ndim - 2)
    integral = np.pad(padded, leading).cumsum(0, dtype=np.float64).cumsum(1)
    width = 2 * radius + 1
    return (
        integral[width:, width:] - integral[:-width, width:]
        - integral[width:, :-width] + integral[:-width, :-width]
    )


def render_visual_water(content, water):
    """Return the display PNG, retaining original coverage in a PNG text field.

    This deliberately permits a local *visual* backdrop inside confirmed water
    where source alpha is missing. The lossless NoWave.SourceCoverage field
    keeps those pixels distinguishable from provider coverage. Unsupported
    holes and land remain transparent. The original coverage is never expanded.
    """
    source = np.array(_rgba(content))
    mask = np.array(water.convert("L"))
    if mask.shape != source.shape[:2]:
        raise ValueError("Unexpected visual water mask dimensions")
    core = (slice(PADDING, PADDING + SIZE), slice(PADDING, PADDING + SIZE))
    donors = (source[:, :, 3] == 255) & (mask == 255)
    result = source.copy()
    allowed = np.zeros(mask.shape, dtype=bool)
    candidates = (source[:, :, 3] < 255) & (mask > 0)
    # Open water and unsupported empty tiles need no reconstruction buffers.
    if candidates[core].any() and np.count_nonzero(donors) >= MIN_DONORS:
        values = np.concatenate(
            (source[:, :, :3] * donors[:, :, None], donors[:, :, None]), axis=2
        )
        # Two 9-pixel boxes form a local triangular weighting with radius 8.
        # Reconstruct only missing display colour; do not blur valid RGB.
        sums = _box_sum(_box_sum(values, RADIUS // 2), RADIUS // 2)
        support = sums[:, :, 3]
        count = _box_sum(donors, RADIUS)
        allowed = candidates & (support >= MIN_SUPPORT * (RADIUS + 1) ** 4) & (count >= MIN_DONORS)
        colours = sums[:, :, :3] / np.maximum(support[:, :, None], 1)
        alpha = source[:, :, 3:4].astype(np.float64) / 255
        blended = np.clip(np.rint(source[:, :, :3] * alpha + colours * (1 - alpha)), 0, 255)
        result[allowed, :3] = blended[allowed].astype(np.uint8)
        result[allowed, 3] = 255
    original = (
        source[core][:, :, 3].astype(np.uint16) * mask[core] // 255
    ).astype(np.uint8)
    result = result[core].copy()
    result[:, :, 3] = result[:, :, 3].astype(np.uint16) * mask[core] // 255
    filled = int(allowed[core].sum())
    metadata = PngImagePlugin.PngInfo()
    metadata.add_text("NoWave.VisualUse", "Local RGB continuity only; no added depth measurement")
    metadata.add_text("NoWave.VisualFillPixels", str(filled))
    if filled:
        metadata.add_text(
            "NoWave.SourceCoverage", base64.b64encode(original.tobytes()).decode(), zip=True
        )
    output = BytesIO()
    Image.fromarray(result).save(output, format="PNG", pnginfo=metadata)
    return output.getvalue()
