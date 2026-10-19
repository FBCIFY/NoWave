"""Author a small cloud atlas from the existing NASA Blue Marble observations.

Offline data preparation only (Pillow/numpy). Does not alter the geographic
globe assets or read the reference photograph. No runtime network dependency.
"""

import hashlib
import io
import json
from pathlib import Path
import urllib.request

import numpy as np
from PIL import Image, ImageFilter

ASSETS = Path(__file__).resolve().parents[1] / 'assets' / 'globe'
PROVENANCE = json.loads((ASSETS / 'provenance.json').read_text())['clouds']


def main():
    raw = urllib.request.urlopen(PROVENANCE['url'], timeout=30).read()
    assert hashlib.sha256(raw).hexdigest() == PROVENANCE['sha256']
    source = Image.open(io.BytesIO(raw)).convert('L')
    size = 512
    atlas = Image.new('RGBA', (size * 3, size))
    axis = np.linspace(-1, 1, size)
    x, y = np.meshgrid(axis, axis)
    # Transparent irregular margins, never an opaque rectangular cloud sheet.
    radius = np.sqrt((x / .98) ** 2 + (y / .88) ** 2)
    edge = np.clip((1 - radius) / .32, 0, 1)
    edge = edge * edge * (3 - 2 * edge)
    crops = [(400, 620, 720, 940), (1300, 100, 1620, 420),
             (1550, 520, 1870, 840)]
    for i, box in enumerate(crops):
        tile = source.crop(box).resize((size, size), Image.Resampling.LANCZOS)
        detail = np.array(tile.filter(ImageFilter.GaussianBlur(.7)), dtype=float) / 255
        mass = np.array(tile.filter(ImageFilter.GaussianBlur(11)), dtype=float) / 255
        density = np.clip((detail - .12) / .6, 0, 1)
        density = density * density * (3 - 2 * density)
        alpha = density ** .8 * edge
        # Cool diffuse shadows and lit tops, encoded once instead of GPU blur.
        light = np.clip(.76 + .24 * mass + .08 * (detail - mass), 0, 1)
        rgb = np.stack([light * .96, light * .98, light], axis=-1)
        rgba = np.concatenate([rgb, alpha[:, :, None]], axis=-1)
        atlas.paste(Image.fromarray(np.uint8(rgba * 255)), (i * size, 0))
    output = ASSETS / 'cloud-passage-atlas.png'
    atlas.save(output, optimize=True)
    (ASSETS / 'cloud-passage-provenance.json').write_text(json.dumps({
        'source': PROVENANCE, 'crops': crops, 'tile_size': size,
        'sha256': hashlib.sha256(output.read_bytes()).hexdigest(),
        'description': 'Three decorative cloud banks, derived from NASA data; not live weather.',
    }, indent=2) + '\n')
    print(output.name, output.stat().st_size, 'bytes')


if __name__ == '__main__':
    main()
