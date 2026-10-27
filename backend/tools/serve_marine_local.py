"""Run the branch's API and bundled GEBCO tiles for a physical-phone recipe.

Only this local entry point reads the optional fault file. It never adds a
network-accessible control endpoint to the production application.
"""

import argparse
import asyncio
import json
import os
from pathlib import Path
import sys
import tarfile
import tempfile

import uvicorn
from fastapi.staticfiles import StaticFiles


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8014)
    parser.add_argument("--fault-file", type=Path)
    args = parser.parse_args()
    repository = Path(__file__).resolve().parents[2]
    sys.path.insert(0, str(repository / "backend"))
    with tempfile.TemporaryDirectory(prefix="nowave-marine-local-") as temporary:
        directory = Path(temporary)
        os.environ["MARINE_CACHE_DIR"] = str(directory / "cache")
        with tarfile.open(repository / "deploy/marine/gebco-2026-v2.tar.gz") as archive:
            archive.extractall(directory / "seafloor", filter="data")

        from app.main import app
        from app.api.routes.map_tiles import _marine_unavailable

        app.mount("/api/v1/map/seafloor", StaticFiles(directory=directory / "seafloor"))

        if args.fault_file:
            @app.middleware("http")
            async def controlled_marine_network(request, call_next):
                path = request.url.path
                if path.startswith("/api/v1/map/") and path.endswith((".png", ".pbf", ".geojson")):
                    try:
                        raw = args.fault_file.read_bytes()
                        mode = json.loads(raw) if len(raw) <= 4096 else {}
                        if not isinstance(mode, dict):
                            mode = {}
                    except (OSError, ValueError):
                        mode = {}
                    delay = mode.get("delay_ms", 0)
                    if isinstance(delay, (int, float)) and delay > 0:
                        await asyncio.sleep(min(delay, 20000) / 1000)
                    if mode.get("unavailable") is True:
                        return _marine_unavailable("Local marine outage simulation.")
                return await call_next(request)

        uvicorn.run(app, host=args.host, port=args.port)


if __name__ == "__main__":
    main()
