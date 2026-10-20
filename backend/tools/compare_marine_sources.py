"""Explicit live display probes; never part of pytest and never a tile prefetcher.

One requested viewport tile per zone. Reuses the persistent upstream HTTP cache.
Run from the repository: PYTHONPATH=backend python backend/tools/compare_marine_sources.py --output ...
"""

import argparse
import asyncio
import json
import math
from collections import Counter
from pathlib import Path

from shapely.ops import transform

from app.application.services.marine_merge import merge_features
from app.domain.marine import MarineFamily, PortInfrastructureFeature
from app.domain.marine_tile import Tile, project
from app.infrastructure.marine.encoding import properties
from app.infrastructure.marine.runtime import close_marine_service, get_marine_service

ZONES = {
    "toulon": (5.93, 43.09),
    "miami": (-80.15, 25.77),
    "vancouver": (-123.1, 49.3),
    "sydney": (151.22, -33.85),
    "auckland": (174.77, -36.84),
    "toulon-saint-mandrier": (5.9326, 43.0835),
    "toulon-osm-only": (5.96755, 43.10407),
    "miami-official-only": (-80.1496, 25.79278),
}


def tile_at(lon, lat, z=12):
    n = 1 << z
    return Tile(
        z,
        int((lon + 180) / 360 * n),
        int((1 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2 * n),
    )


def sample(feature, nearest=None):
    from shapely.geometry import mapping

    return {
        "type": "Feature",
        "geometry": mapping(feature.geometry),
        "properties": {**properties(feature), "nearest_other_m": nearest},
    }


def visible_port(f):
    return f.infrastructure_type in {
        "pier",
        "pontoon",
        "breakwater",
        "groyne",
        "dock",
    } or (
        f.infrastructure_type == "quay"
        and f.geometry.geom_type in {"Polygon", "MultiPolygon"}
    )


def distant_examples(features, others, tile):
    factor = math.cos(math.radians((tile.bounds[1] + tile.bounds[3]) / 2))

    def projection(lon, lat):
        return tuple(v * factor for v in project(lon, lat))

    other_shapes = [transform(projection, f.geometry) for f in others]
    found = []
    for f in features:
        if isinstance(f, PortInfrastructureFeature) and not visible_port(f):
            continue
        if not tile.polygon.contains(f.geometry.centroid):
            continue
        g = transform(projection, f.geometry)
        distance = min((g.distance(o) for o in other_shapes), default=1e9)
        if distance >= 20:
            found.append((distance, f))
    return [
        sample(f, round(d, 1) if other_shapes else None)
        for d, f in sorted(found, key=lambda pair: (-pair[0], pair[1].id))[:3]
    ]


async def compare(output, zones, zoom):
    service = get_marine_service()
    report = {
        "date": "2026-10-16",
        "scope": "Requested XYZ viewport; counts exclude the tile buffer. Official-only means unmatched, not proof of absence in the complete OSM database.",
        "zones": {},
    }
    try:
        for name in zones:
            tile = tile_at(*ZONES[name], z=zoom)
            zone = {"tile": [tile.z, tile.x, tile.y], "bbox": tile.bounds}
            for family in MarineFamily:
                providers = service.select(tile, family)
                batches = await asyncio.gather(
                    *(p.fetch(tile, family) for p in providers), return_exceptions=True
                )
                by_provider, failures = {}, {}
                for p, b in zip(providers, batches):
                    if isinstance(b, Exception):
                        by_provider[p.id] = []
                        failures[p.id] = type(b).__name__
                    else:
                        by_provider[p.id] = [
                            f for f in b.features if f.geometry.intersects(tile.polygon)
                        ]
                        if b.failures:
                            failures[p.id] = b.failures
                fallback_id = "openwaters" if family == MarineFamily.SEAMARKS else "osm"
                fallback = by_provider.get(fallback_id, [])
                raw = [
                    f for id, fs in by_provider.items() if id != fallback_id for f in fs
                ]
                official_merge = merge_features(raw, tile.bounds)
                official = official_merge.features
                merged = merge_features([*official, *fallback], tile.bounds)
                matched_official = {a for a, b in merged.matches}
                absorbed_fallback = {b for a, b in merged.matches}
                official_only = [f for f in official if f.id not in matched_official]
                osm_only = [f for f in fallback if f.id not in absorbed_fallback]
                output_tile = await service.get_tile(tile, family)
                import mapbox_vector_tile

                decoded = mapbox_vector_tile.decode(output_tile.content)
                detail = {
                    "providers": {k: len(fs) for k, fs in by_provider.items()},
                    "failures": failures,
                    "official_raw": len(raw),
                    "official_distinct": len(official),
                    "official_scale_matches": len(official_merge.matches),
                    "fallback": len(fallback),
                    "high_confidence_matches": len(merged.matches),
                    "official_only": len(official_only),
                    "osm_only": len(osm_only),
                    "conflicts": len(merged.conflicts),
                    "result": len(merged.features),
                    "mvt_bytes": len(output_tile.content),
                    "mvt_layer_counts_with_buffer": {
                        k: len(v["features"]) for k, v in decoded.items()
                    },
                    "official_types": dict(
                        Counter(
                            f.type
                            if family == MarineFamily.SEAMARKS
                            else f.infrastructure_type
                            for f in official
                        )
                    ),
                    "fallback_types": dict(
                        Counter(
                            f.type
                            if family == MarineFamily.SEAMARKS
                            else f.infrastructure_type
                            for f in fallback
                        )
                    ),
                    "matches": merged.matches[:15],
                    "conflict_pairs": merged.conflicts[:15],
                    "official_only_samples": distant_examples(
                        official_only, fallback, tile
                    ),
                    "osm_only_samples": distant_examples(osm_only, official, tile),
                }
                zone[family.value] = detail
                print(
                    name,
                    family.value,
                    {
                        k: v
                        for k, v in detail.items()
                        if k
                        in {
                            "providers",
                            "official_distinct",
                            "fallback",
                            "high_confidence_matches",
                            "conflicts",
                            "result",
                        }
                    },
                    flush=True,
                )
            report["zones"][name] = zone
            output.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
    finally:
        await close_marine_service()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--zone", choices=list(ZONES), action="append")
    parser.add_argument("--zoom", type=int, choices=[12, 14], default=12)
    args = parser.parse_args()
    asyncio.run(
        compare(
            args.output,
            args.zone or ["toulon", "miami", "vancouver", "sydney", "auckland"],
            args.zoom,
        )
    )
