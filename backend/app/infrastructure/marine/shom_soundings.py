"""Small, verified official XYZ survey releases; never samples a DTM or image.

Files retain original public Shom XYZ rows, identified by checksums and DOI.
Large releases are spatially selected offline with the original row numbers.
No network download or multi-million-point survey processing on a tile request.
"""

import hashlib
import json
from functools import lru_cache
from pathlib import Path

from shapely.geometry import Point, box
from shapely.strtree import STRtree

from app.domain.hydrography import Sounding
from app.domain.marine import MarineFamily, ProviderBatch

DATA = Path(__file__).with_name("data") / "shom-surveys"
HEADER = "long(DD),lat(DD),depth(m - down positive - LAT)"


@lru_cache(maxsize=1)
def survey_soundings():
    features = []
    for survey in json.loads((DATA / "manifest.json").read_text())["surveys"]:
        content = (DATA / survey["file"]).read_bytes()
        if hashlib.sha256(content).hexdigest() != survey["sha256"]:
            raise ValueError("Shom survey checksum mismatch")
        lines = content.decode("utf-8").splitlines()
        if "selection" in survey:
            if survey["selection"]["source_header"][1:] != [survey["id"], HEADER]:
                raise ValueError("Unverified Shom selected-row schema")
            rows = [(record["row"], record["xyz"]) for record in map(json.loads, lines)]
        else:
            if lines[1:3] != [survey["id"], HEADER]:
                raise ValueError("Unverified Shom survey schema")
            rows = list(enumerate(lines[3:], start=4))
        if len(rows) != survey["count"] or len({r for r, _ in rows}) != len(rows):
            raise ValueError("Unverified Shom survey schema or count")
        for row, line in rows:
            lon, lat, depth = map(float, line.split(","))
            identifier = f"{survey['id']}:{row}"
            features.append(
                Sounding(
                    id=f"shom-surveys:{identifier}",
                    source="shom-surveys",
                    source_id=identifier,
                    source_priority=100,
                    geometry=Point(lon, lat),
                    source_geometry_type="Point",
                    source_updated_at=survey["revision"],
                    source_date=survey["acquisition_end"][:10],
                    scale="survey",
                    provenance=(
                        survey["doi"],
                        survey["download_url"],
                        survey["sha256"],
                        survey["archive_sha256"],
                        *(
                            [survey["selection"]["source_xyz_sha256"]]
                            if "selection" in survey
                            else []
                        ),
                    ),
                    source_attributes=json.dumps(
                        dict(
                            survey=survey["id"],
                            row=row,
                            xyz=line,
                            acquisition_start=survey["acquisition_start"],
                            acquisition_end=survey["acquisition_end"],
                        ),
                        separators=(",", ":"),
                    ),
                    value_original=depth,
                    value_m=depth,
                    unit_original="m",
                    vertical_datum="LAT",
                    sounding_datum="LAT",
                    datum_reference=survey["metadata_url"],
                    derivation="published_survey_sample",
                    license=survey["license"],
                    # No numerical per-sample uncertainty is published here.
                    quality="Shom controlled and qualified survey; per-sample uncertainty unpublished",
                )
            )
    return tuple(features)


@lru_cache(maxsize=1)
def survey_index():
    return STRtree([f.geometry for f in survey_soundings()])


class ShomSoundingProvider:
    id = "shom-surveys"

    def covers(self, tile, family):
        return family == MarineFamily.SOUNDINGS and bool(
            len(survey_index().query(box(*tile.query_bounds), predicate="intersects"))
        )

    async def fetch(self, tile, family):
        # Include the full selection neighbourhood at each zoom, so tile edges
        # do not choose a deeper point than the adjacent tile in the same cell.
        region = box(*tile.parent(14).query_bounds)
        indices = survey_index().query(region, predicate="intersects")
        return ProviderBatch(tuple(survey_soundings()[i] for i in sorted(indices)))
