#!/usr/bin/env python3
"""Build the offline, visual-only GEBCO overview. No provider calls at runtime.

Uses a pinned 2 arc-minute subset of GEBCO 2026 (every eighth native cell).
The 15 arc-second original is not a uniform survey-resolution guarantee.
Run with the project's locked Python dependencies (numpy and Pillow).
"""

import argparse
import gzip
import hashlib
from io import BytesIO
import json
from pathlib import Path
import struct
import tarfile
import urllib.request

import numpy as np
from PIL import Image

VERSION = "gebco-2026-v1"
MAX_ZOOM = 6
SIZE = 256
SHAPE = (5400, 10800)
SOURCE_SHA256 = "8257fc17fcde87799d44db91f868374aa62185dd9ec2cdab243f564cb596db99"
SOURCE_URL = (
    "https://dap.ceda.ac.uk/thredds/dodsC/bodc/gebco/global/gebco_2026/"
    "ice_surface_elevation/netcdf/GEBCO_2026.nc.dods"
    "?elevation[0:8:43199][0:8:86399]"
)
TID_SHA256 = "efc26561bbe69100ac9de3e0f98881af7e8422338707c7f71ad17f12f63ac5fe"
TID_URL = (
    "https://dap.ceda.ac.uk/thredds/dodsC/bodc/gebco/global/gebco_2026/"
    "type_identifier_grid/netcdf/gebco_2026_tid.nc.dods"
    "?tid[0:8:43199][0:8:86399]"
)
# Display palette only. No sounding or contour is produced from this overview.
DEPTHS = (0, 200, 1000, 3000, 6000, 11000)
COLOURS = ((97, 170, 164), (14, 105, 133), (1, 74, 107),
           (0, 50, 90), (0, 45, 81), (0, 23, 49))


def load_grid(path, expected_hash=SOURCE_SHA256, dtype=">i4"):
    with path.open("rb") as stream:
        if hashlib.file_digest(stream, "sha256").hexdigest() != expected_hash:
            raise ValueError("GEBCO subset checksum mismatch")
        stream.seek(0)
        header = stream.read(4096)
    start = header.index(b"\nData:\n") + len(b"\nData:\n")
    count = SHAPE[0] * SHAPE[1]
    if struct.unpack(">II", header[start:start + 8]) != (count, count):
        raise ValueError("Unexpected GEBCO DAP2 array")
    # DAP2 Int16 values are XDR signed 32-bit integers on the wire.
    return np.memmap(path, dtype=dtype, mode="r", offset=start + 8, shape=SHAPE)


def sample_tile(grid, tid, z, x, y):
    """Bilinear global pixel lattice, longitude wrap, pixel-centred source.

    Interpolate ocean values separately so positive land cannot become a
    fictitious coastal depth. Alpha retains the sampled ocean fraction.
    """
    world = SIZE * (1 << z)
    lon = ((x * SIZE + np.arange(SIZE) + .5) / world) * 360 - 180
    lat = np.degrees(np.arctan(np.sinh(
        np.pi * (1 - 2 * (y * SIZE + np.arange(SIZE) + .5) / world)
    )))
    # Native grid centres start half a 15 arc-second cell inside the bounds.
    gx = (lon + 180 - 1 / 480) * 30
    gy = np.clip((lat + 90 - 1 / 480) * 30, 0, grid.shape[0] - 1)
    ix, iy = np.floor(gx).astype(int), np.floor(gy).astype(int)
    fx, fy = gx - ix, gy - iy
    covered = np.zeros((SIZE, SIZE), dtype=np.float64)
    depth = np.zeros_like(covered)
    for dy in (0, 1):
        for dx in (0, 1):
            index = (
                np.minimum(iy + dy, grid.shape[0] - 1)[:, None],
                ((ix + dx) % grid.shape[1])[None, :],
            )
            values = grid[index]
            # TID 0 is GEBCO's land classification. Negative elevation alone
            # would incorrectly colour dry depressions below sea level.
            ocean = (values < 0) & (tid[index] != 0)
            weight = ((fy if dy else 1 - fy)[:, None]
                      * (fx if dx else 1 - fx)[None, :]) * ocean
            covered += weight
            depth += -values * weight
    depth /= np.maximum(covered, 1e-12)
    return depth, covered


def colour_tile(depth, covered):
    # Quantized visual colours and transparent land. The WebP compression
    # affects display RGB only: these pixels never supply numerical depths.
    index = np.clip(np.rint(depth / 11000 * 254), 0, 254).astype(np.uint8) + 1
    index[covered < .5] = 0
    image = Image.fromarray(index, "P")
    palette = np.zeros((256, 3), dtype=np.uint8)
    for channel in range(3):
        palette[1:, channel] = np.rint(np.interp(
            np.linspace(0, 11000, 255), DEPTHS,
            [colour[channel] for colour in COLOURS],
        ))
    image.putpalette(palette.ravel().tolist())
    output = BytesIO()
    image.info["transparency"] = 0
    image.convert("RGBA").save(output, format="WEBP", quality=82, method=4)
    return output.getvalue()


def add_file(archive, name, content):
    entry = tarfile.TarInfo(name)
    entry.size = len(content)
    entry.mode = 0o644
    entry.mtime = 0
    archive.addfile(entry, BytesIO(content))


def build(source, classification, output, max_zoom=MAX_ZOOM):
    grid = load_grid(source)
    tid = load_grid(classification, TID_SHA256, "u1")
    manifest = {
        "version": VERSION, "dataset": "GEBCO_2026", "source": SOURCE_URL,
        "source_sha256": SOURCE_SHA256, "doi": "10.5285/4f68d5c7-45eb-f999-e063-7086abc036fa",
        "land_mask_source": TID_URL, "land_mask_sha256": TID_SHA256,
        "sample_arc_minutes": 2, "maxzoom": max_zoom, "tile_size": SIZE,
        "tile_count": sum(4 ** z for z in range(max_zoom + 1)), "format": "webp",
        "usage": "Visual overview only; not for navigation. No depth labels or contours derived.",
        "attribution": "GEBCO Bathymetric Compilation Group 2026 (2026); sampled and coloured by NoWave",
        "license": "https://www.gebco.net/data-products/gridded-bathymetry/terms-of-use",
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_suffix(".tmp")
    with temporary.open("wb") as raw, gzip.GzipFile(
        filename="", mode="wb", fileobj=raw, mtime=0
    ) as compressed, tarfile.open(fileobj=compressed, mode="w|") as archive:
        add_file(archive, f"{VERSION}/manifest.json", json.dumps(manifest, indent=2).encode() + b"\n")
        for z in range(max_zoom + 1):
            for x in range(1 << z):
                for y in range(1 << z):
                    depth, covered = sample_tile(grid, tid, z, x, y)
                    add_file(archive, f"{VERSION}/{z}/{x}/{y}.webp", colour_tile(depth, covered))
            print(f"Prepared GEBCO zoom {z}", flush=True)
    temporary.replace(output)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="Pinned DAP2 subset on disk")
    parser.add_argument("classification", type=Path, help="Pinned GEBCO TID land classification subset")
    parser.add_argument("output", type=Path, help="Generated .tar.gz pyramid")
    parser.add_argument("--download", action="store_true", help="Download the public pinned subset first")
    args = parser.parse_args()
    if args.download:
        urllib.request.urlretrieve(SOURCE_URL, args.source)
        urllib.request.urlretrieve(TID_URL, args.classification)
    build(args.source, args.classification, args.output)
