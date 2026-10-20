"""Real official coastal objects survive normalization, fusion and MVT."""

import json
import math
from dataclasses import replace
from pathlib import Path

import mapbox_vector_tile
import pytest
from shapely.geometry import Point

from app.application.services.marine_merge import merge_features
from app.domain.marine import MarineFamily
from app.domain.marine_tile import Tile
from app.infrastructure.marine.encoding import encode_tile
from app.infrastructure.marine.normalization import seamark

RECORDS = json.loads(
    (
        Path(__file__).parents[1] / "fixtures/marine/seamarks-coast-audit.json"
    ).read_text()
)


@pytest.mark.parametrize(
    "record", RECORDS, ids=lambda r: r["source"] + ":" + r["expected"]["id"]
)
def test_real_official_object_survives_source_to_normalized_to_mvt(record):
    feature = seamark(
        record["raw"],
        record["type"],
        source=record["source"],
        dataset=record["dataset"],
        priority=100,
    )
    for field, value in record["expected"].items():
        assert getattr(feature, field) == value
    lon, lat = feature.geometry.coords[0]
    tile = Tile(
        14,
        int((lon + 180) / 360 * 2**14),
        int((1 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2 * 2**14),
    )
    merged = merge_features([feature], tile.bounds)
    data = mapbox_vector_tile.decode(
        encode_tile(tile, MarineFamily.SEAMARKS, merged.features)
    )
    rows = data["seamark"]["features"]
    assert len(rows) == 1
    props = rows[0]["properties"]
    assert props["id"] == feature.id and props["type"] == record["type"]
    assert props["navigation_system"] == feature.navigation_system
    assert props["color"] == feature.color and props["category"] == feature.category


def test_two_distinct_nearby_real_fixed_laterals_never_collapse():
    marks = [
        seamark(
            r["raw"], r["type"], source=r["source"], dataset=r["dataset"], priority=100
        )
        for r in RECORDS
        if r["expected"]["color"] in ["green_grey", "red_grey"]
    ]
    assert len(marks) == 2
    # Deliberately collocate the two genuine IDs: neither distance nor a shared
    # family establishes identity, and the source side/colour conflicts survive.
    marks = [replace(mark, geometry=Point(7.13, 43.588)) for mark in marks]
    result = merge_features(marks, (7.12, 43.58, 7.14, 43.60))
    assert len(result.features) == 2 and not result.matches
