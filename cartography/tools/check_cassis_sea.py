"""Check that the real vector water mask fully protects sea from hillshade."""
import json
from pathlib import Path
import sys
import numpy as np
from PIL import Image
from shapely import contains_xy
from shapely.geometry import shape

root = Path(sys.argv[1])
a = np.asarray(Image.open(root/'sea-without-hillshade.png').convert('RGB'))
b = np.asarray(Image.open(root/'sea-with-hillshade.png').convert('RGB'))
water = shape(json.loads((root/'water-screen.json').read_text())).buffer(-2)
y, x = np.mgrid[:a.shape[0], :a.shape[1]]
# Attribution changes when the hillshade layer is hidden; exclude its UI strip.
# This is not map data. The remaining sea is compared pixel for pixel.
mask = contains_xy(water, x+.5, y+.5) & (y < a.shape[0]-45)
changed = np.any(a != b, axis=2)
result = {'sea_pixels_compared': int(mask.sum()), 'sea_pixels_changed': int((changed & mask).sum()),
          'land_pixels_changed': int((changed & ~contains_xy(water, x+.5, y+.5) & (y < a.shape[0]-45)).sum()), 'coast_edge_excluded_px': 2, 'attribution_ui_excluded_px': 45}
(root/'pixel-check.json').write_text(json.dumps(result, indent=2)+'\n')
print(json.dumps(result))
if not result['sea_pixels_compared'] or result['sea_pixels_changed'] or not result['land_pixels_changed']:
    raise SystemExit('Hillshade water protection failed or hillshade never rendered')
