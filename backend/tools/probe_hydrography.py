"""On-demand live hydrographic tile audit; no OSM pyramid prefetch.

.venv/bin/python backend/tools/probe_hydrography.py --output <directory>
Records normalized values, MVT counts/bytes/timing, actual upstream/cache counters.
"""

import argparse
import asyncio
import json
import math
from pathlib import Path
import sys
import time

sys.path.insert(0, str(Path(__file__).parents[1]))
import mapbox_vector_tile
from app.domain.marine import MarineFamily
from app.domain.marine_tile import Tile
from app.infrastructure.marine.runtime import get_marine_service, close_marine_service

ZONES = [
    ("toulon", 5.93, 43.08),
    ("saint-mandrier", 5.93, 43.055),
    ("giens", 6.12, 43.035),
    ("marseille", 5.35, 43.29),
    ("miami", -80.15, 25.74),
    ("cape-florida", -80.155, 25.67),
    ("miami-rock", -80.1253611, 25.7075),
]
FAMILIES = [
    (MarineFamily.CONTOURS, 12),
    (MarineFamily.CONTOURS, 14),
    (MarineFamily.HAZARDS, 14),
    (MarineFamily.SOUNDINGS, 14),
    (MarineFamily.SOUNDINGS, 15),
    (MarineFamily.SOUNDINGS, 16),
]


def tile_at(lon, lat, z):
    n = 1 << z
    return Tile(
        z,
        int((lon + 180) / 360 * n),
        int((1 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2 * n),
    )


async def probe(directory):
    directory.mkdir(parents=True, exist_ok=True)
    service = get_marine_service()
    metrics = service.providers[0].http.metrics
    records = []
    try:
        for zone, lon, lat in ZONES:
            for family, z in FAMILIES:
                tile = tile_at(lon, lat, z)
                before = dict(metrics)
                start = time.perf_counter()
                try:
                    result = await service.get_tile(tile, family)
                except Exception as error:
                    records.append(
                        dict(
                            zone=zone,
                            family=family.value,
                            tile=[z, tile.x, tile.y],
                            error=type(error).__name__,
                        )
                    )
                    continue
                elapsed = (time.perf_counter() - start) * 1000
                layers = mapbox_vector_tile.decode(result.content)
                features = [f for l in layers.values() for f in l["features"]]
                record = dict(
                    zone=zone,
                    family=family.value,
                    tile=[z, tile.x, tile.y],
                    features=len(features),
                    bytes=len(result.content),
                    ms=round(elapsed, 2),
                    sources=result.sources,
                    failures=result.failures,
                    network_requests=metrics["network_requests"]
                    - before["network_requests"],
                    http_cache_hits=metrics["cache_hits"] - before["cache_hits"],
                    depths=sorted(
                        {
                            f["properties"]["value_m"]
                            for f in features
                            if "value_m" in f["properties"]
                        }
                    ),
                    types=sorted(
                        {f["properties"].get("hazard_type", "") for f in features}
                    ),
                    examples=[f["properties"] for f in features[:3]],
                )
                start = time.perf_counter()
                cached = await service.get_tile(tile, family)
                record["tile_cache_ms"] = round((time.perf_counter() - start) * 1000, 3)
                assert cached.content == result.content
                neighbour = Tile(z, min((1 << z) - 1, tile.x + 1), tile.y)
                before = dict(metrics)
                start = time.perf_counter()
                try:
                    adjacent = await service.get_tile(neighbour, family)
                    record["neighbour"] = dict(
                        bytes=len(adjacent.content),
                        ms=round((time.perf_counter() - start) * 1000, 2),
                        network_requests=metrics["network_requests"]
                        - before["network_requests"],
                        http_cache_hits=metrics["cache_hits"] - before["cache_hits"],
                        failures=adjacent.failures,
                    )
                except Exception as error:
                    record["neighbour"] = dict(error=type(error).__name__)
                records.append(record)
                (directory / f"{zone}-{family.value}-z{z}.pbf").write_bytes(
                    result.content
                )
                print(
                    zone,
                    family.value,
                    z,
                    len(features),
                    len(result.content),
                    record["ms"],
                    record["failures"],
                    flush=True,
                )
        (directory / "measurements.json").write_text(
            json.dumps(records, indent=2) + "\n"
        )
    finally:
        await close_marine_service()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    asyncio.run(probe(parser.parse_args().output))
