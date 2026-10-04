"""Build XYZ Web Mercator raster tiles from a georeferenced RGBA bathymetry image."""

import argparse
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image
from rasterio.transform import from_bounds
from rasterio.warp import Resampling, reproject, transform_bounds


WEB_MERCATOR_LIMIT = 20037508.342789244
MAX_LATITUDE = 85.05112878


def tile_x(lon, zoom):
    n = 2 ** zoom
    return max(0, min(n - 1, int(math.floor((lon + 180.0) / 360.0 * n))))


def tile_y(lat, zoom):
    lat = max(-MAX_LATITUDE, min(MAX_LATITUDE, lat))
    rad = math.radians(lat)
    n = 2 ** zoom
    value = (1.0 - math.asinh(math.tan(rad)) / math.pi) / 2.0 * n
    return max(0, min(n - 1, int(math.floor(value))))


def mercator_tile_bounds(x, y, zoom):
    n = 2 ** zoom
    span = 2 * WEB_MERCATOR_LIMIT / n

    left = -WEB_MERCATOR_LIMIT + x * span
    right = left + span
    top = WEB_MERCATOR_LIMIT - y * span
    bottom = top - span

    return left, bottom, right, top


def build_tiles(source, bbox, output, min_zoom, max_zoom):
    image = Image.open(source).convert("RGBA")
    rgba = np.asarray(image, dtype=np.float32)

    height, width = rgba.shape[:2]
    west, south, east, north = bbox

    src_transform = from_bounds(
        west,
        south,
        east,
        north,
        width,
        height,
    )

    alpha = rgba[:, :, 3] / 255.0

    # Premultiplied alpha prevents dark halos around transparent NoData areas
    # during bilinear reprojection.
    rgb_premultiplied = rgba[:, :, :3] * alpha[:, :, None]

    output.mkdir(parents=True, exist_ok=True)

    tile_count = 0

    for zoom in range(min_zoom, max_zoom + 1):
        xmin = tile_x(west, zoom)
        xmax = tile_x(east, zoom)
        ymin = tile_y(north, zoom)
        ymax = tile_y(south, zoom)

        for x in range(xmin, xmax + 1):
            for y in range(ymin, ymax + 1):
                bounds = mercator_tile_bounds(x, y, zoom)

                dst_transform = from_bounds(
                    *bounds,
                    256,
                    256,
                )

                dst_alpha = np.zeros((256, 256), dtype=np.float32)
                dst_rgb_premultiplied = np.zeros(
                    (256, 256, 3),
                    dtype=np.float32,
                )

                reproject(
                    source=alpha,
                    destination=dst_alpha,
                    src_transform=src_transform,
                    src_crs="EPSG:4326",
                    dst_transform=dst_transform,
                    dst_crs="EPSG:3857",
                    resampling=Resampling.bilinear,
                    dst_nodata=0.0,
                )

                for channel in range(3):
                    reproject(
                        source=rgb_premultiplied[:, :, channel],
                        destination=dst_rgb_premultiplied[:, :, channel],
                        src_transform=src_transform,
                        src_crs="EPSG:4326",
                        dst_transform=dst_transform,
                        dst_crs="EPSG:3857",
                        resampling=Resampling.bilinear,
                        dst_nodata=0.0,
                    )

                dst_rgba = np.zeros((256, 256, 4), dtype=np.uint8)

                visible = dst_alpha > 1e-6

                for channel in range(3):
                    values = np.zeros((256, 256), dtype=np.float32)
                    values[visible] = (
                        dst_rgb_premultiplied[:, :, channel][visible]
                        / dst_alpha[visible]
                    )
                    dst_rgba[:, :, channel] = np.clip(
                        values,
                        0,
                        255,
                    ).astype(np.uint8)

                dst_rgba[:, :, 3] = np.clip(
                    dst_alpha * 255,
                    0,
                    255,
                ).astype(np.uint8)

                target = output / str(zoom) / str(x) / f"{y}.png"
                target.parent.mkdir(parents=True, exist_ok=True)

                Image.fromarray(dst_rgba, "RGBA").save(
                    target,
                    optimize=True,
                )

                tile_count += 1

    metadata = {
        "schema": 1,
        "format": "xyz",
        "tile_size": 256,
        "crs": "EPSG:3857",
        "source_crs": "EPSG:4326",
        "bbox": list(bbox),
        "minzoom": min_zoom,
        "maxzoom": max_zoom,
        "tiles": tile_count,
    }

    (output / "metadata.json").write_text(
        json.dumps(metadata, indent=2) + "\n"
    )

    return metadata


def build_region_tiles(manifest_path, bbox, output, min_zoom, max_zoom):
    """Read only one output tile at a time from the sparse premultiplied RGBA VRT."""
    import os
    import rasterio
    from rasterio.vrt import WarpedVRT
    from rasterio.windows import Window
    from pipeline_io import atomic_json, digest, fingerprint
    manifest = json.loads(manifest_path.read_text())
    generation = Path(manifest['rgba_vrt']).parent
    for block in manifest['blocks']:
        if digest(generation / block['rgba']) != block['rgba_sha256']:
            raise ValueError('Corrupt colour block; rerun prepare_region before tiling')
    if not 0 <= min_zoom <= max_zoom <= 18:
        raise ValueError('Expected 0 <= minzoom <= maxzoom <= 18')
    # Two display samples per finest effective source/grid cell at the northern edge.
    effective = max(manifest['resolution_m'], min(p['resolution_m'] for p in manifest['products']))
    native_zoom = math.ceil(math.log2(156543.033928 * math.cos(math.radians(bbox[3])) / effective))
    if max_zoom > native_zoom + 1:
        raise ValueError(f'maxzoom {max_zoom} exceeds justified limit {native_zoom + 1}; use MapLibre overzoom')
    signature = fingerprint({'field': manifest['signature'], 'bbox': bbox,
        'minzoom': min_zoom, 'maxzoom': max_zoom, 'code': digest(Path(__file__))})
    output.mkdir(parents=True, exist_ok=True)
    index_path = output / 'metadata.json'
    previous = json.loads(index_path.read_text()) if index_path.exists() else {}
    previous_tiles = previous.get('checksums', {}) if previous.get('signature') == signature else {}
    checksums = {}
    west, south, east, north = bbox
    with rasterio.Env(GDAL_CACHEMAX=64 * 1024 * 1024), rasterio.open(manifest['rgba_vrt']) as src:
        block_bounds = []
        for block in manifest['blocks']:
            if block['valid_cells']:
                window = Window(block['col'], block['row'], block['size'], block['size'])
                block_bounds.append(transform_bounds(src.crs, 'EPSG:4326', *src.window_bounds(window)))
        for zoom in range(min_zoom, max_zoom + 1):
            dimension = 256 * 2**zoom
            affine = from_bounds(-WEB_MERCATOR_LIMIT, -WEB_MERCATOR_LIMIT,
                                  WEB_MERCATOR_LIMIT, WEB_MERCATOR_LIMIT, dimension, dimension)
            options = dict(crs='EPSG:3857', transform=affine, width=dimension, height=dimension,
                           dtype='float32', warp_mem_limit=64)
            with WarpedVRT(src, resampling=Resampling.bilinear, **options) as smooth, \
                 WarpedVRT(src, resampling=Resampling.nearest, **options) as support:
                candidates = set()
                for bw, bs, be, bn in block_bounds:
                    for x in range(tile_x(max(west, bw), zoom), tile_x(min(east, be), zoom) + 1):
                        for y in range(tile_y(min(north, bn), zoom), tile_y(max(south, bs), zoom) + 1):
                            candidates.add((x, y))
                for x, y in sorted(candidates):
                    name = f'{zoom}/{x}/{y}.png'
                    target = output / name
                    # Each tile has an atomic checkpoint, including interrupted runs.
                    stamp = target.with_suffix('.json')
                    checkpoint = json.loads(stamp.read_text()) if stamp.exists() else {}
                    expected = previous_tiles.get(name) or (checkpoint.get('sha256') if checkpoint.get('signature') == signature else None)
                    if target.exists() and expected and digest(target) == expected:
                        checksums[name] = expected
                        continue
                    window = Window(x * 256, y * 256, 256, 256)
                    rgba = smooth.read(window=window)
                    alpha = np.clip(rgba[3] / 255, 0, 1)
                    # Bilinear colours may not extend coverage into a missing source cell.
                    valid = (support.read(4, window=window) > 0) & (alpha > 1e-6)
                    if not valid.any():
                        continue  # Missing tile = no coverage, never a zero-depth tile.
                    result = np.zeros((256, 256, 4), dtype='uint8')
                    for c in range(3):
                        result[:, :, c][valid] = np.clip(rgba[c][valid] / alpha[valid], 0, 255).astype('uint8')
                    result[:, :, 3][valid] = np.clip(alpha[valid] * 255, 0, 255).astype('uint8')
                    target.parent.mkdir(parents=True, exist_ok=True)
                    temporary = target.with_suffix('.tmp.png')
                    Image.fromarray(result).save(temporary)
                    os.replace(temporary, target)
                    checksums[name] = digest(target)
                    atomic_json(stamp, {'signature': signature, 'sha256': checksums[name]})
    # Remove stale PNGs only from this generated tile output, after a successful rebuild.
    for stale in output.glob('*/*/*.png'):
        if str(stale.relative_to(output)) not in checksums:
            stale.unlink()
    metadata = {'schema': 1, 'format': 'xyz', 'crs': 'EPSG:3857', 'tile_size': 256,
        'minzoom': min_zoom, 'maxzoom': max_zoom, 'bbox': list(bbox), 'tiles': len(checksums),
        'signature': signature, 'field_signature': manifest['signature'], 'checksums': checksums,
        'source_resolution_m': [p['resolution_m'] for p in manifest['products']],
        'grid_resolution_m': manifest['resolution_m'], 'coverage_complete': False, 'empty_tiles_omitted': True}
    atomic_json(index_path, metadata)
    return metadata


def main():
    parser = argparse.ArgumentParser(description=__doc__)

    inputs = parser.add_mutually_exclusive_group(required=True)
    inputs.add_argument("--input", type=Path)
    inputs.add_argument("--field-manifest", type=Path)
    parser.add_argument("--output", required=True, type=Path)

    parser.add_argument(
        "--bbox",
        nargs=4,
        required=True,
        type=float,
        metavar=("WEST", "SOUTH", "EAST", "NORTH"),
    )

    parser.add_argument("--min-zoom", type=int, default=10)
    parser.add_argument("--max-zoom", type=int, default=14)

    args = parser.parse_args()

    if args.min_zoom > args.max_zoom:
        parser.error("--min-zoom must be <= --max-zoom")

    builder = build_region_tiles if args.field_manifest else build_tiles
    metadata = builder(
        args.field_manifest or args.input,
        tuple(args.bbox),
        args.output,
        args.min_zoom,
        args.max_zoom,
    )

    print(json.dumps(metadata, indent=2))


if __name__ == "__main__":
    main()
