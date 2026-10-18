"""Reproject NASA geographic rasters for the native Mapbox globe.

Run with a Python environment containing Pillow and numpy. Inputs are downloaded
only by this offline authoring tool; the app never contacts NASA at runtime.
The reference photograph is intentionally not an input.
"""

import hashlib
import io
import json
import pathlib
import urllib.request

import numpy as np
from PIL import Image

DEST = pathlib.Path(__file__).resolve().parents[1] / 'assets' / 'globe'
CLOUDS = 'https://eoimages.gsfc.nasa.gov/images/imagerecords/57000/57747/cloud_combined_2048.jpg'
MOON = 'https://svs.gsfc.nasa.gov/vis/a000000/a004700/a004720/lroc_color_poles_1k.jpg'


def read(url):
    raw = urllib.request.urlopen(url, timeout=30).read()
    return Image.open(io.BytesIO(raw)), hashlib.sha256(raw).hexdigest()


def main():
    DEST.mkdir(parents=True, exist_ok=True)
    clouds, cloud_hash = read(CLOUDS)
    clouds = np.array(clouds.convert('L'), dtype=float) / 255
    size = 512
    # A 1024-square Mercator world split into four native ImageSources.
    # Pixel-centred samples keep identical borders at the equator and meridian.
    coord = (np.arange(size * 2) + .5) / (size * 2)
    lon = (coord * 2 - 1) * np.pi
    lat = np.arctan(np.sinh(np.pi * (1 - 2 * coord)))
    x = np.minimum((coord * clouds.shape[1]).astype(int), clouds.shape[1] - 1)
    y = np.minimum(((.5 - lat / np.pi) * clouds.shape[0]).astype(int), clouds.shape[0] - 1)
    alpha_cloud = np.clip((clouds[y[:, None], x[None, :]] - .045) / .955, 0, 1) ** 1.15 * .78
    # Fixed artistic sun at 35 W / 35 N, not a clock or meteorological product.
    incidence = (np.sin(lat[:, None]) * np.sin(np.deg2rad(35)) +
                 np.cos(lat[:, None]) * np.cos(np.deg2rad(35)) *
                 np.cos(lon[None, :] + np.deg2rad(35)))
    dusk = np.clip((.38 - incidence) / .7, 0, 1)
    alpha_night = dusk * dusk * (3 - 2 * dusk) * .82
    # Premultiplied 'night over cloud', stored as ordinary straight-alpha PNG.
    alpha = alpha_night + alpha_cloud * (1 - alpha_night)
    rgb = np.divide(alpha_cloud * (1 - alpha_night), alpha,
                    out=np.zeros_like(alpha), where=alpha > 0)
    rgba = np.stack([rgb, rgb, rgb, alpha], axis=-1)
    raster = Image.fromarray(np.uint8(np.clip(rgba, 0, 1) * 255))
    for name, box in zip(['nw', 'ne', 'sw', 'se'],
                         [(0, 0, 512, 512), (512, 0, 1024, 512),
                          (0, 512, 512, 1024), (512, 512, 1024, 1024)]):
        raster.crop(box).save(DEST / f'{name}.png', optimize=True)

    # Orthographic projection of the LRO near side, at only 128 px.
    moon, moon_hash = read(MOON)
    texture = np.array(moon.convert('RGB'), dtype=float)
    axis = (np.arange(128) + .5) / 64 - 1
    mx, my = np.meshgrid(axis, -axis)
    rr = mx * mx + my * my
    mz = np.sqrt(np.maximum(0, 1 - rr))
    mlon = np.arctan2(mx, mz)
    mlat = np.arcsin(np.clip(my, -1, 1))
    tx = np.clip(((mlon / (2 * np.pi) + .5) * texture.shape[1]).astype(int), 0, texture.shape[1] - 1)
    ty = np.clip(((.5 - mlat / np.pi) * texture.shape[0]).astype(int), 0, texture.shape[0] - 1)
    light = .6 + .4 * np.maximum(0, -.25 * mx + .2 * my + .947 * mz)
    pixels = np.zeros((128, 128, 4), dtype=np.uint8)
    pixels[:, :, :3] = np.clip(texture[ty, tx] * light[:, :, None] * 1.4, 0, 255)
    pixels[:, :, 3] = np.clip((1 - np.sqrt(rr)) * 64 + .5, 0, 1) * 255
    Image.fromarray(pixels).save(DEST / 'moon.png', optimize=True)
    (DEST / 'provenance.json').write_text(json.dumps({
        'clouds': {'url': CLOUDS, 'sha256': cloud_hash},
        'moon': {'url': MOON, 'sha256': moon_hash},
        'outputs': {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                    for p in sorted(DEST.glob('*.png'))},
    }, indent=2) + '\n')
    print('PNG bytes:', sum(p.stat().st_size for p in DEST.glob('*.png')))


if __name__ == '__main__':
    main()
