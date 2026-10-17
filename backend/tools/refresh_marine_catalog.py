"""Refresh official routing masks and verified NOAA layer IDs (explicit live tool).

Does not download OSM tiles or national feature archives. Review the generated
catalog and the source licences before deploying; this is not a background job.
"""

import argparse
import asyncio
import json
from datetime import datetime, timezone
from pathlib import Path

import httpx
from shapely.geometry import Polygon, mapping, shape
from shapely.ops import unary_union

SCALES = ["overview", "general", "coastal", "approach", "harbour", "berthing"]
BASE = "https://encdirect.noaa.gov/arcgis/rest/services/encdirect"
SHOM = "https://services.data.shom.fr/INSPIRE/wfs"
KINDS = {
    "Cardinal": "buoy_cardinal",
    "Isolated_Danger": "buoy_isolated_danger",
    "Lateral": "buoy_lateral",
    "Safe_Water": "buoy_safe_water",
    "Special_Purpose_General": "buoy_special_purpose",
}


async def refresh(directory):
    async with httpx.AsyncClient(
        timeout=30, headers={"User-Agent": "NoWave marine catalog (https://no-wave.fr)"}
    ) as http:

        async def get(url, params=None):
            response = await http.get(url, params=params)
            response.raise_for_status()
            data = response.json()
            if "error" in data:
                raise ValueError(data["error"])
            return data

        shom = []
        for kind in ["au_exclusive_economic_zone", "au_territorial_sea"]:
            data = await get(
                SHOM,
                dict(
                    service="WFS",
                    version="1.0.0",
                    request="GetFeature",
                    typeName=f"ESPACES_MARITIMES_BDD_WFS:{kind}",
                    outputFormat="json",
                    maxFeatures=1000,
                    srsName="EPSG:4326",
                ),
            )
            if len(data["features"]) >= 1000:
                raise ValueError("Truncated SHOM coverage")
            shom.extend(shape(f["geometry"]) for f in data["features"])
        # Include land holes and a conservative coastal strip for internal waters
        # behind straight baselines (e.g. Toulon). This only permits requests;
        # it never suppresses a global fallback.
        filled = [
            Polygon(p.exterior)
            for g in shom
            for p in (list(g.geoms) if g.geom_type == "MultiPolygon" else [g])
        ]
        coverage = {
            "shom": mapping(
                unary_union(filled)
                .simplify(0.01, preserve_topology=True)
                .buffer(0.25, quad_segs=1)
            )
        }
        noaa = []
        counts = {}
        for i, scale in enumerate(SCALES):
            count = 0
            for offset in range(0, 10000, 1000):
                data = await get(
                    f"{BASE}/enc_coverage/MapServer/{i}/query",
                    dict(
                        f="geojson",
                        where="1=1",
                        outFields="*",
                        outSR=4326,
                        returnGeometry="true",
                        resultRecordCount=1000,
                        resultOffset=offset,
                    ),
                )
                noaa.extend(shape(f["geometry"]) for f in data["features"])
                count += len(data["features"])
                if not data.get("exceededTransferLimit"):
                    break
            else:
                raise ValueError("Truncated NOAA coverage")
            counts[scale] = count
        coverage["noaa"] = mapping(
            unary_union(noaa)
            .simplify(0.01, preserve_topology=True)
            .buffer(0.02, quad_segs=1)
        )
        layers = []
        for rank, scale in enumerate(SCALES, 1):
            data = await get(f"{BASE}/enc_{scale}/MapServer/layers", {"f": "json"})
            for l in data["layers"]:
                n = l["name"]
                kind = None
                if ".Buoy_" in n:
                    kind = KINDS.get(n.split(".Buoy_")[1].removesuffix("_point"))
                elif ".Beacon_" in n:
                    kind = KINDS.get(n.split(".Beacon_")[1].removesuffix("_point"))
                    kind = kind.replace("buoy_", "beacon_") if kind else None
                elif n.endswith(".Light_point"):
                    kind = "light"
                elif n.endswith(".Landmark_point"):
                    # Provider retains only CATLMK=tower + FUNCTN=light support.
                    kind = "lighthouse"
                elif n.endswith(".Topmark_point"):
                    kind = "topmark"
                elif n.endswith(
                    (".Shoreline_Construction_line", ".Shoreline_Construction_area")
                ):
                    kind = "construction"
                elif n.endswith(".Dock_Area"):
                    kind = "dock"
                if kind:
                    extent = l["extent"]
                    layers.append(
                        dict(
                            scale=scale,
                            rank=rank,
                            layer=l["id"],
                            kind=kind,
                            name=n,
                            bounds=[
                                extent[k] for k in ["xmin", "ymin", "xmax", "ymax"]
                            ],
                        )
                    )
        if not layers:
            raise ValueError("Missing NOAA layers")
        directory.mkdir(parents=True, exist_ok=True)
        (directory / "coverage.json").write_text(
            json.dumps(coverage, separators=(",", ":")) + "\n"
        )
        (directory / "noaa_layers.json").write_text(json.dumps(layers, indent=2) + "\n")
        (directory / "catalog.json").write_text(
            json.dumps(
                {
                    "retrieved_at": datetime.now(timezone.utc).isoformat(),
                    "shom_url": SHOM,
                    "shom_classes": [
                        "au_exclusive_economic_zone",
                        "au_territorial_sea",
                    ],
                    "shom_attribution": "Shom, Espaces maritimes de souveraineté et de juridiction, Licence Ouverte 2.0",
                    "noaa_url": BASE,
                    "noaa_coverage_counts": counts,
                    "noaa_layer_count": len(layers),
                    "noaa_license": "CC0 1.0; NOAA Office of Coast Survey",
                    "routing_only": "Simplified, buffered masks, not legal boundaries. Global fallbacks always retained.",
                },
                indent=2,
            )
            + "\n"
        )


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--output", type=Path, required=True)
    asyncio.run(refresh(p.parse_args().output))
