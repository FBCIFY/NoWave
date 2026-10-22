"""Offline replay of the exact WMS inputs and OSM masks collected for NW-220."""
import base64
import json
import sys
from io import BytesIO
from pathlib import Path

import numpy as np
from PIL import Image

from app.infrastructure.adapters.emodnet_bathymetry import recolor_bathymetry_png, feather_coverage
from app.infrastructure.marine.visual_water import PADDING, render_visual_water

root = Path(sys.argv[1])
results = []
for folder in sorted(root.glob('*-*-*')):
    if not (folder / 'source.png').exists():
        continue
    recolored = Image.open(BytesIO(recolor_bathymetry_png((folder / 'source.png').read_bytes(), associated_alpha=True))).convert('RGBA')
    context = feather_coverage(recolored)
    content = BytesIO()
    context.save(content, format='PNG')
    water = Image.open(folder / 'water-context.png').convert('L')
    png = render_visual_water(content.getvalue(), water)
    expected = Image.open(folder / 'final.png')
    result = Image.open(BytesIO(png))
    assert np.array_equal(np.array(result), np.array(expected)), folder.name
    assert result.info == expected.info, folder.name
    mask = np.array(water)[PADDING:-PADDING, PADDING:-PADDING]
    a = np.array(context.getchannel('A'))[PADDING:-PADDING, PADDING:-PADDING]
    coverage = (a.astype(np.uint16) * mask // 255).astype(np.uint8)
    saved = result.info.get('NoWave.SourceCoverage')
    restored = np.frombuffer(base64.b64decode(saved), dtype=np.uint8).reshape(256, 256) if saved else np.array(result.getchannel('A'))
    assert np.array_equal(restored, coverage)
    assert np.all(np.array(result.getchannel('A')) <= mask)
    results.append({'tile': folder.name, 'pixels_identical': True, 'coverage_identical': True})
print(json.dumps(results, indent=2))
