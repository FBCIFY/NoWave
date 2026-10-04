"""Verify browser captures: opaque sea unchanged, terrain visibly shaded."""
import json
import sys
from pathlib import Path
from PIL import Image

output = Path(sys.argv[1])
results = {}
for area in ('cassis', 'la-ciotat', 'marseille'):
    before = Image.open(output/f'{area}-before.png').convert('RGB')
    after = Image.open(output/f'{area}-after.png').convert('RGB')
    assert before.size == after.size
    # The attribution control changes when the attributed DEM is hidden.
    # Compare the map pixels above this 24 px UI strip, not the control text.
    before = before.crop((0, 126, before.width, before.height-24))
    after = after.crop((0, 126, after.width, after.height-24))
    sea_count = changed_sea = changed_land = 0
    for a, b in zip(before.get_flattened_data(), after.get_flattened_data()):
        if a == (12, 47, 80):
            sea_count += 1
            changed_sea += a != b
        elif a != b:
            changed_land += 1
    assert sea_count > 1000, f'{area}: no substantial sea area in view'
    assert changed_sea == 0, f'{area}: hillshade changed {changed_sea} opaque sea pixels'
    assert changed_land > 1000, f'{area}: hillshade not perceptible on land'
    results[area] = {'opaque_sea_pixels': sea_count, 'changed_sea_pixels': changed_sea,
                     'changed_other_pixels': changed_land}
print(json.dumps(results, indent=2))
(output/'pixel-check.json').write_text(json.dumps(results, indent=2)+'\n')
