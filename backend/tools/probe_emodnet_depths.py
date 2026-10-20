"""Eight sequential, bounded live tile checks; outputs summaries, never CSV/MVT.

Run from the repository: PYTHONPATH=backend .venv/bin/python backend/tools/probe_emodnet_depths.py
No server startup, database, phone, persistent response cache or bulk download.
"""

import asyncio
import json
import math
import time

import httpx
import mapbox_vector_tile

from app.domain.marine_tile import Tile, unproject
from app.infrastructure.marine.emodnet_depths import PROVIDER_ID, grid_selection
from app.infrastructure.marine.runtime import get_marine_service, close_marine_service
from app.main import app

REGIONS = (
    ("Toulon", 5.97, 43.09),
    ("Marseille", 5.30, 43.24),
    ("Ajaccio", 8.70, 41.90),
    ("Golfe de Gascogne", -2.80, 46.00),
    ("Manche", -1.55, 49.75),
    ("Mer du Nord", 3.10, 51.50),
    ("Baltique", 14.00, 55.20),
    ("Adriatique", 14.00, 44.80),
)


async def main():
    service = get_marine_service()
    provider = next(p for p in service.providers if p.id == PROVIDER_ID)
    try:
        async with httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app), base_url="http://nowave.local"
        ) as client:
            for name, lon, lat in REGIONS:
                z = 14
                tile = Tile(
                    z,
                    int((lon + 180) / 360 * 2**z),
                    int(
                        (1 - math.asinh(math.tan(math.radians(lat))) / math.pi)
                        / 2
                        * 2**z
                    ),
                )
                selection = grid_selection(tile)
                before_bytes = provider.metrics["bytes"]
                before_requests = provider.metrics["requests"]
                started = time.monotonic()
                response = await client.get(
                    f"/api/v1/map/soundings/{z}/{tile.x}/{tile.y}.pbf"
                )
                elapsed = (time.monotonic() - started) * 1000
                record = dict(
                    region=name,
                    tile=f"{z}/{tile.x}/{tile.y}",
                    http=response.status_code,
                    state=response.headers.get("x-nowave-marine-status"),
                    cache_control=response.headers.get("cache-control"),
                    requested_cells=selection.count if selection else 0,
                    erddap_requests=provider.metrics["requests"] - before_requests,
                    csv_bytes=provider.metrics["bytes"] - before_bytes,
                    route_ms=round(elapsed, 2),
                )
                if response.status_code == 200:
                    features = mapbox_vector_tile.decode(response.content)["sounding"][
                        "features"
                    ]
                    record.update(
                        mvt_points=len(features), mvt_bytes=len(response.content)
                    )
                    assert len(features) <= 64
                    w, s, e, n = tile.bounds
                    west, south, east, north = tile.mercator_bounds
                    samples = []
                    for feature in features:
                        p = feature["properties"]
                        assert p["value_m"] > 0 and p["value_original"] == -p["value_m"]
                        assert (
                            p["source"] == "EMODnet"
                            and p["nature"] == "modeled_grid_cell"
                        )
                        x, y = feature["geometry"]["coordinates"]
                        assert 0 <= x <= 4096 and 0 <= y <= 4096
                        lon, lat = unproject(
                            west + x / 4096 * (east - west),
                            south + y / 4096 * (north - south),
                        )
                        assert (
                            w - 1e-9 <= lon <= e + 1e-9 and s - 1e-9 <= lat <= n + 1e-9
                        )
                        if len(samples) < 3:
                            samples.append(
                                dict(
                                    lon=round(lon, 6),
                                    lat=round(lat, 6),
                                    depth_m=p["value_m"],
                                    label=p["depth_label"],
                                )
                            )
                    record["samples"] = samples
                    record["sign_coordinates_valid"] = True
                print(json.dumps(record, ensure_ascii=False), flush=True)
    finally:
        await close_marine_service()


if __name__ == "__main__":
    asyncio.run(main())
