"""Real fixed-aid excerpts and conservative qualification / fusion regressions."""

import asyncio
import json
from dataclasses import replace
from pathlib import Path

import httpx
import mapbox_vector_tile
import pytest
from shapely.geometry import Point

from app.application.services.marine_merge import merge_features
from app.domain.marine import MarineFamily, SeamarkFeature
from app.domain.marine_tile import Tile
from app.infrastructure.marine.encoding import encode_tile
from app.infrastructure.marine.http import MarineHTTP
from app.infrastructure.marine.normalization import (
    attach_light,
    lighthouse_structure,
    seamark,
)
from app.infrastructure.marine.providers import (
    OpenWatersProvider,
    ShomProvider,
    NoaaProvider,
)

FIXTURE = json.loads(
    (Path(__file__).parents[1] / "fixtures/marine/fixed-aids.json").read_text()
)


def test_real_toulon_fixed_cardinals_keep_category_bands_shape_and_light():
    for raw in FIXTURE["shom_bcncar"]:
        mark = seamark(
            raw, "beacon_cardinal", source="shom", dataset="bcncar", priority=100
        )
        assert mark.category in {"north", "south", "east", "west"}
        assert mark.color_pattern == "horizontal"
        assert mark.shape == "pile"
        assert mark.navigation_system == "IALA_A"
        assert mark.type != "buoy_cardinal"
    light = FIXTURE["shom_lights"][0]
    linked = attach_light(mark, light)
    assert linked.light_range == float(light["properties"]["valnmr"])
    assert linked.light_character == str(light["properties"]["litchr"])
    assert linked.provenance[-1].startswith("shom:light:FR")


def test_real_miami_beacons_iala_b_never_region_a():
    marks = [
        seamark(raw, "beacon_lateral", source="noaa", dataset="harbour:1", priority=105)
        for raw in FIXTURE["noaa_1"]
    ]
    assert [(m.category, m.color, m.navigation_system) for m in marks] == [
        ("port", "green", "IALA_B"),
        ("starboard", "red", "IALA_B"),
    ]
    assert all(m.type == "beacon_lateral" for m in marks)


def test_lighthouse_needs_explicit_light_support_tower_not_name_or_range():
    cape = FIXTURE["noaa_26"][0]
    assert lighthouse_structure(cape)
    assert not lighthouse_structure(FIXTURE["noaa_26"][1])
    raw = json.loads(json.dumps(cape))
    raw["properties"]["FUNCTN"] = "lighting"
    assert not lighthouse_structure(raw)
    raw["properties"]["FUNCTN"] = "33"
    raw["properties"]["CATLMK"] = "mast"
    assert not lighthouse_structure(raw)
    assert lighthouse_structure(FIXTURE["shom_lndmrk"][0])


def test_light_metadata_survives_mvt_without_sector_geometry_or_text():
    raw = FIXTURE["shom_lights"][0]
    mark = seamark(raw, "light", source="shom", dataset="lights", priority=100)
    mark = replace(
        mark, geometry=Point(5.93, 43.09)
    )  # Geometry isolated for this encoder test.
    props = mapbox_vector_tile.decode(
        encode_tile(Tile(12, 2115, 1503), MarineFamily.SEAMARKS, [mark])
    )["seamark"]["features"][0]["properties"]
    assert props["light_range"] == float(raw["properties"]["valnmr"])
    assert props["light_character"] == str(raw["properties"]["litchr"])
    assert props["light_color"]
    assert "light_group" in props and "light_period" in props
    assert props["type"] == "light"
    assert "sectr1" not in props


def test_all_requested_beacon_types_remain_distinct_from_buoys_and_lights():
    # Synthetic domain inputs exercise absent-in-local-tile classes too.
    kinds = ["lateral", "cardinal", "safe_water", "isolated_danger", "special_purpose"]
    features = [
        SeamarkFeature(
            id=k,
            source="test",
            source_id=k,
            source_priority=1,
            geometry=Point(5.93, 43.09),
            type="beacon_" + k,
        )
        for k in kinds
    ]
    features += [
        replace(features[0], id="b", source_id="b", type="buoy_lateral"),
        replace(features[0], id="l", source_id="l", type="light"),
        replace(features[0], id="h", source_id="h", type="lighthouse"),
    ]
    assert len(merge_features(features, (5.9, 43, 6, 44)).features) == 8


def test_colocated_light_sectors_with_different_characteristics_do_not_merge():
    base = SeamarkFeature(
        id="a",
        source="shom",
        source_id="a",
        source_priority=100,
        geometry=Point(5.93, 43.09),
        type="light",
        name="Light",
        color="red",
        light_character="2",
    )
    other = replace(
        base,
        id="b",
        source="openwaters",
        source_id="b",
        source_priority=10,
        light_character="1",
    )
    assert len(merge_features([base, other], (5.9, 43, 6, 44)).features) == 2


def test_openwaters_keeps_lights_as_lights_and_ignores_inferred_default_range(tmp_path):
    # Synthetic transport exercises upstream's documented default, not an integration claim.
    data = mapbox_vector_tile.encode(
        [
            {
                "name": "seamark",
                "features": [
                    {
                        "geometry": Point(2000, 2000),
                        "properties": {
                            "type": "light_major",
                            "osm_id": 1,
                            "light_range": 9,
                        },
                    },
                    {
                        "geometry": Point(2100, 2000),
                        "properties": {
                            "type": "light_minor",
                            "osm_id": 2,
                            "light_range": 20,
                            "seamark:light:range": "20",
                            "seamark:light:character": "Fl",
                        },
                    },
                    {
                        "geometry": Point(2200, 2000),
                        "properties": {
                            "type": "landmark",
                            "osm_id": 3,
                            "category": "tower",
                            "function": "lighting",
                        },
                    },
                ],
            }
        ]
    )

    async def run():
        http = MarineHTTP(
            tmp_path / "ow.sqlite",
            httpx.MockTransport(lambda _: httpx.Response(200, content=data)),
        )
        try:
            marks = (
                await OpenWatersProvider(http).fetch(
                    Tile(12, 2115, 1503), MarineFamily.SEAMARKS
                )
            ).features
            assert [m.type for m in marks] == ["light", "light"]
            assert marks[0].light_range is None
            assert marks[1].light_range == 20 and marks[1].light_character == "Fl"
            assert all(m.navigation_system == "" for m in marks)
        finally:
            await http.close()

    asyncio.run(run())


def test_official_adapters_use_verified_classes_and_skip_unqualified_landmarks(
    tmp_path,
):
    def handler(r):
        if r.url.host == "services.data.shom.fr":
            key = "shom_" + r.url.params["typeName"].split(":")[1]
        else:
            key = "noaa_" + r.url.path.split("/")[-2]
        return httpx.Response(
            200, json={"type": "FeatureCollection", "features": FIXTURE.get(key, [])}
        )

    async def run():
        http = MarineHTTP(tmp_path / "sources.sqlite", httpx.MockTransport(handler))
        try:
            shom = await ShomProvider(http).fetch(
                Tile(12, 2115, 1503), MarineFamily.SEAMARKS
            )
            noaa = await NoaaProvider(http).fetch(
                Tile(12, 1136, 1745), MarineFamily.SEAMARKS
            )
            assert not shom.failures and not noaa.failures
            assert {"beacon_cardinal", "beacon_lateral", "light", "lighthouse"} <= {
                m.type for m in shom.features
            }
            lighthouses = [m for m in noaa.features if m.type == "lighthouse"]
            assert lighthouses and all(
                m.name == "Cape Florida Light" for m in lighthouses
            )
        finally:
            await http.close()

    asyncio.run(run())


def test_osm_numbered_light_metadata_preserved_without_sector_inference():
    from app.infrastructure.marine.normalization import osm_light_attributes

    light = osm_light_attributes(
        {
            "light_range": 9,
            "light_color": "red",
            "seamark:light:1:colour": "white;red",
            "seamark:light:1:character": "Fl",
            "seamark:light:1:range": "12",
            "seamark:light:2:colour": "green",
        }
    )
    assert light["light_range"] is None
    assert light["light_color"] == "white_red_green"
    assert ("seamark:light:1:range", "12") in light["light_details"]


@pytest.mark.parametrize(
    "key,kind,source,color,pattern",
    [
        (
            "shom_bcnisd",
            "beacon_isolated_danger",
            "shom",
            "black_red_black",
            "horizontal",
        ),
        ("noaa_safe", "beacon_safe_water", "noaa", "red_white", "vertical"),
    ],
)
def test_real_sparse_classes_are_qualified_without_inventing_objects(
    key, kind, source, color, pattern
):
    raw = FIXTURE[key][0]
    mark = seamark(raw, kind, source=source, dataset=key, priority=100)
    assert mark.color == color and mark.color_pattern == pattern
    assert mark.navigation_system == "IALA_B"  # Martinique / NOAA, both actually B.
