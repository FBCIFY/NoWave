"""Load and validate a NoWave cartography region definition."""

import argparse
import json
from pathlib import Path


def load_region(path: Path) -> dict:
    region = json.loads(path.read_text())

    if region.get("schema") != 1:
        raise ValueError("Unsupported region schema")

    for key in ("id", "name", "bbox", "center", "zoom", "coverage", "sources"):
        if key not in region:
            raise ValueError(f"Missing region field: {key}")

    bbox = region["bbox"]
    if not isinstance(bbox, list) or len(bbox) != 4:
        raise ValueError("bbox must contain [west, south, east, north]")

    west, south, east, north = map(float, bbox)

    if not -180 <= west < east <= 180:
        raise ValueError("Invalid longitude bounds")

    if not -90 <= south < north <= 90:
        raise ValueError("Invalid latitude bounds")

    center = region["center"]
    if not isinstance(center, list) or len(center) != 2:
        raise ValueError("center must contain [longitude, latitude]")

    lon, lat = map(float, center)

    if not west <= lon <= east or not south <= lat <= north:
        raise ValueError("center must be inside bbox")

    zoom = float(region["zoom"])
    if not 4 <= zoom <= 18:
        raise ValueError("zoom must be between 4 and 18")

    coverage = region["coverage"]
    if float(coverage.get("sea_buffer_nm", 0)) <= 0:
        raise ValueError("sea_buffer_nm must be positive")

    required_sources = {"vector", "bathymetry", "relief"}
    missing_sources = required_sources - set(region["sources"])
    if missing_sources:
        raise ValueError(
            "Missing sources: " + ", ".join(sorted(missing_sources))
        )

    return region


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("region", type=Path)
    args = parser.parse_args()

    region = load_region(args.region)

    print(json.dumps(region, indent=2, ensure_ascii=False))
    print()
    print(f"OK - région valide: {region['id']}")


if __name__ == "__main__":
    main()
