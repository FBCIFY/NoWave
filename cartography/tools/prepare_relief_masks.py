"""Sea overpaint masks, leaving original bathymetry and nautical data untouched."""
import io
import json
import math
from pathlib import Path
from urllib.request import urlopen
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
MAPZEN = 'https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png'


def demo_mask():
    bathy = Image.open(ROOT/'assets/demo-bathymetry.png').convert('RGBA')
    width, height = bathy.size
    alpha = Image.new('L', bathy.size, 255)
    draw = ImageDraw.Draw(alpha)
    data = json.loads((ROOT/'data/demo.geojson').read_text())
    for feature in data['features']:
        if feature['properties']['kind'] != 'land':
            continue
        rings = feature['geometry']['coordinates']
        for index, ring in enumerate(rings):
            pixels = [((lon+.3)/.6*width, (.3-lat)/.6*height) for lon, lat in ring]
            draw.polygon(pixels, fill=0 if index == 0 else 255)
    bathy.putalpha(alpha)
    bathy.save(ROOT/'assets/demo-sea-mask.png')


def tile_corner(x, y, z):
    return [x/2**z*360-180, math.degrees(math.atan(math.sinh(math.pi*(1-2*y/2**z))))]


def real_preview_mask():
    # Twenty-five z12 tiles cover Marseille/Cassis and surroundings; no fabricated coast.
    z, x0, y0, columns, rows = 12, 2108, 1499, 5, 5
    sea = Image.new('RGBA', (256*columns, 256*rows))
    for row in range(rows):
        for col in range(columns):
            url = MAPZEN.format(z=z, x=x0+col, y=y0+row)
            print('Reading real DEM:', url, flush=True)
            with urlopen(url, timeout=30) as response:
                tile = Image.open(io.BytesIO(response.read())).convert('RGB')
            mask = Image.new('RGBA', (256, 256))
            pixels = [(12, 47, 80, 255) if r*256+g+b/256-32768 <= 0 else (0, 0, 0, 0)
                      for r, g, b in tile.get_flattened_data()]
            mask.putdata(pixels)
            sea.paste(mask, (col*256, row*256))
    # Close narrow zero-elevation coastal rings introduced by resampling the DEM.
    # This only regularizes the diagnostic display mask; elevations stay untouched.
    alpha = sea.getchannel('A').filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.MinFilter(3))
    sea = Image.new('RGBA', sea.size, (12, 47, 80, 0))
    sea.putalpha(alpha)
    sea.save(ROOT/'assets/mapzen-preview-sea-mask.png')
    coordinates = [tile_corner(x0, y0, z), tile_corner(x0+columns, y0, z),
                   tile_corner(x0+columns, y0+rows, z), tile_corner(x0, y0+rows, z)]
    (ROOT/'assets/mapzen-preview-sea-mask.json').write_text(json.dumps({
        'coordinates': coordinates, 'source': MAPZEN,
        'method': 'Terrarium elevation <= 0 metres, 3-pixel morphological water closing; preview only, not a surveyed coastline',
        'zoom': z, 'tiles': [x0, y0, columns, rows],
    }, indent=2)+'\n')


if __name__ == '__main__':
    demo_mask()
    real_preview_mask()
