"""Explicit metadata refresh. No tiles/archive prefetch and no credentials.

Run from the repository: .venv/bin/python backend/tools/refresh_hydro_catalog.py
Review the diff before deploying changed upstream schemas.
"""

import argparse
import asyncio
import json
from pathlib import Path

import httpx

BASE = "https://encdirect.noaa.gov/arcgis/rest/services/encdirect"
KINDS = [
    ("Sounding_Datum_area", "sounding_datum"),
    ("Depth_Contour_line", "depth_contour"),
    ("Sounding_point", "sounding"),
    ("Underwater_Awash_Rock", "rock"),
    ("Wreck_", "wreck"),
    ("Obstruction_", "obstruction"),
]


async def refresh(output):
    layers = []
    async with httpx.AsyncClient(
        timeout=30,
        headers={"User-Agent": "NoWave marine metadata (https://no-wave.fr)"},
    ) as http:
        for rank, scale in enumerate(
            ["general", "coastal", "approach", "harbour", "berthing"], 2
        ):
            response = await http.get(
                f"{BASE}/enc_{scale}/MapServer/layers", params={"f": "json"}
            )
            response.raise_for_status()
            for layer in response.json()["layers"]:
                kind = next((v for k, v in KINDS if k in layer["name"]), None)
                if kind is None:
                    continue
                extent = layer["extent"]
                layers.append(
                    dict(
                        scale=scale,
                        rank=rank,
                        layer=layer["id"],
                        kind=kind,
                        name=layer["name"],
                        geometry_type=layer["geometryType"],
                        bounds=[extent[k] for k in ["xmin", "ymin", "xmax", "ymax"]],
                        fields=[f["name"] for f in layer["fields"]],
                    )
                )
    if not layers:
        raise ValueError("No verified hydrographic layers")
    output.write_text(json.dumps(layers, indent=2) + "\n")
    print(f"{len(layers)} verified layers written to {output}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output",
        type=Path,
        default=Path(__file__).parents[1]
        / "app/infrastructure/marine/data/hydro_layers.json",
    )
    asyncio.run(refresh(parser.parse_args().output))
