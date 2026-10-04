"""Build XYZ Web Mercator raster tiles from a georeferenced RGBA bathymetry image."""

import argparse
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image
from rasterio.transform import from_bounds
from rasterio.warp import Resampling, reproject


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


def main():
    parser = argparse.ArgumentParser(description=__doc__)

    parser.add_argument("--input", required=True, type=Path)
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

    metadata = build_tiles(
        args.input,
        tuple(args.bbox),
        args.output,
        args.min_zoom,
        args.max_zoom,
    )

    print(json.dumps(metadata, indent=2))


if __name__ == "__main__":
    main()
