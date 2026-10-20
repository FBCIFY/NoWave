"""Explicit live outage/recovery probe, using real global fallback tiles."""

import argparse
import asyncio
import hashlib
import json
import tempfile
from pathlib import Path

import httpx
import mapbox_vector_tile

from app.application.services.marine_tiles import MarineTileService
from app.domain.marine import MarineFamily
from app.domain.marine_tile import Tile
from app.infrastructure.marine.http import MarineHTTP
from app.infrastructure.marine.ign import IgnPortProvider
from app.infrastructure.marine.providers import (
    OpenWatersProvider,
    ShomProvider,
    ShortbreadProvider,
)
from app.infrastructure.marine.runtime import close_marine_service, get_marine_service


async def probe(output):
    normal = get_marine_service()
    tile = Tile(12, 2115, 1503)
    calls = []

    def unavailable(request):
        calls.append(request.url.host)
        return httpx.Response(503)

    report = {
        "tile": [tile.z, tile.x, tile.y],
        "simulation": "HTTP 503 for national hosts, real cached worldwide fallbacks",
        "families": {},
    }
    with tempfile.TemporaryDirectory(prefix="nowave-national-outage-") as directory:
        failed = MarineHTTP(
            Path(directory) / "failed.sqlite", httpx.MockTransport(unavailable)
        )
        global_http = MarineHTTP()
        outage = MarineTileService(
            [
                OpenWatersProvider(global_http),
                ShortbreadProvider(global_http),
                ShomProvider(failed),
                IgnPortProvider(failed),
            ]
        )
        try:
            for family in MarineFamily:
                before = await normal.get_tile(tile, family)
                during = await outage.get_tile(tile, family)
                # A new output cache exercises restoration through the actual merge.
                restored = await MarineTileService(normal.providers).get_tile(
                    tile, family
                )

                def describe(result):
                    return {
                        "sources": result.sources,
                        "failures": result.failures,
                        "layers": {
                            k: len(v["features"])
                            for k, v in mapbox_vector_tile.decode(
                                result.content
                            ).items()
                        },
                        "sha256": hashlib.sha256(result.content).hexdigest(),
                    }

                report["families"][family.value] = {
                    "before": describe(before),
                    "outage": describe(during),
                    "restored": describe(restored),
                }
                assert during.failures and during.sources == (
                    ("openwaters",) if family == MarineFamily.SEAMARKS else ("osm",)
                )
                assert restored.content == before.content and not restored.failures
            report["intercepted_national_requests"] = calls
            output.write_text(json.dumps(report, indent=2) + "\n")
        finally:
            await failed.close()
            await global_http.close()
            await close_marine_service()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    asyncio.run(probe(parser.parse_args().output))
