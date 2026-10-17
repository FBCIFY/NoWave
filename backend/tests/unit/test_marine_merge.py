from dataclasses import replace

import pytest
from shapely.geometry import LineString, MultiPolygon, Point, Polygon

from app.application.services.marine_merge import merge_features
from app.domain.marine import PortInfrastructureFeature, SeamarkFeature

BOUNDS = (-80.2, 25.7, -80.1, 25.8)


def buoy(id="official", source="noaa", **values):
    return SeamarkFeature(
        id=id,
        geometry=Point(-80.15, 25.75),
        source=source,
        source_id=id,
        source_priority=100 if source == "noaa" else 10,
        provenance=(f"{source}:{id}",),
        type="buoy_lateral",
        category="starboard",
        color="red",
        shape="pillar",
        **values,
    )


def port(geometry, id="official", source="noaa", kind="pier", **values):
    return PortInfrastructureFeature(
        id=id,
        geometry=geometry,
        source=source,
        source_id=id,
        source_priority=100 if source == "noaa" else 10,
        provenance=(f"{source}:{id}",),
        infrastructure_type=kind,
        **values,
    )


def test_official_point_wins_and_keeps_both_provenances_deterministically():
    official, osm = buoy(), buoy("osm", "openwaters")
    for inputs in ([official, osm], [osm, official]):
        result = merge_features(inputs, BOUNDS)
        assert len(result.features) == 1
        assert result.features[0].source == "noaa"
        assert result.features[0].provenance == ("noaa:official", "openwaters:osm")
        assert result.matches == [("official", "osm")]


@pytest.mark.parametrize(
    "change",
    [
        {"color": "green"},
        {"category": "port"},
        {"type": "buoy_cardinal"},
        {"topmark_shape": "2_spheres"},
    ],
)
def test_nearby_but_different_buoys_survive(change):
    a = buoy(topmark_shape="cylinder")
    b = replace(buoy("osm", "openwaters", topmark_shape="cylinder"), **change)
    assert len(merge_features([a, b], BOUNDS).features) == 2


def test_distance_alone_is_never_a_match_and_osm_only_survives():
    a = replace(buoy(), category="", color="", shape="")
    b = replace(buoy("osm", "openwaters"), category="", color="", shape="")
    far = replace(buoy("far", "openwaters"), geometry=Point(-80.16, 25.75))
    result = merge_features([a, b, far], BOUNDS)
    assert len(result.features) == 3
    assert result.conflicts


def test_distinct_same_authority_objects_are_not_merged_but_scales_are():
    a, b = buoy(scale="harbour"), buoy("second", scale="harbour")
    assert len(merge_features([a, b], BOUNDS).features) == 2
    b = replace(b, scale="approach", source_priority=99)
    assert len(merge_features([a, b], BOUNDS).features) == 1


@pytest.mark.parametrize("kind", ["pier", "breakwater", "groyne"])
def test_slightly_different_same_line_merges_but_parallel_distinct_lines_do_not(kind):
    line = LineString([(-80.15, 25.75), (-80.149, 25.75)])
    same = LineString([(-80.15, 25.750005), (-80.149, 25.750005)])
    separate = LineString([(-80.15, 25.75005), (-80.149, 25.75005)])
    a = port(line, kind=kind)
    assert (
        len(merge_features([a, port(same, "osm", "osm", kind)], BOUNDS).features) == 1
    )
    assert (
        len(merge_features([a, port(separate, "osm", "osm", kind)], BOUNDS).features)
        == 2
    )


@pytest.mark.parametrize("multi", [False, True])
def test_polygon_matches_and_official_only_osm_only_survive(multi):
    polygon = Polygon(
        [(-80.15, 25.75), (-80.149, 25.75), (-80.149, 25.7501), (-80.15, 25.7501)]
    )
    g = MultiPolygon([polygon]) if multi else polygon
    a = port(g, kind="quay")
    b = port(g, "osm", "osm", "quay")
    c = port(
        Polygon(
            [(-80.14, 25.75), (-80.139, 25.75), (-80.139, 25.7501), (-80.14, 25.7501)]
        ),
        "osm-only",
        "osm",
        "pier",
    )
    result = merge_features([a, b, c], BOUNDS)
    assert {f.id for f in result.features} == {"official", "osm-only"}
    assert len(merge_features([a], BOUNDS).features) == 1


def test_adjacent_disjoint_quay_polygons_are_not_duplicates():
    a = Polygon(
        [(-80.15, 25.75), (-80.149, 25.75), (-80.149, 25.7501), (-80.15, 25.7501)]
    )
    b = Polygon(
        [
            (-80.15, 25.75011),
            (-80.149, 25.75011),
            (-80.149, 25.75021),
            (-80.15, 25.75021),
        ]
    )
    assert len(merge_features([port(a), port(b, "osm", "osm")], BOUNDS).features) == 2


def test_invalid_or_reversed_crs_is_rejected():
    with pytest.raises(ValueError):
        replace(buoy(), geometry=Point(500000, 4800000))


def test_fallback_point_with_two_equally_compatible_official_candidates_is_kept():
    a = buoy()
    b = replace(buoy("second"), geometry=Point(-80.14999, 25.75))
    osm = replace(buoy("osm", "openwaters"), geometry=Point(-80.149995, 25.75))
    result = merge_features([a, b, osm], BOUNDS)
    assert len(result.features) == 3 and result.conflicts


def test_parallel_quays_one_metre_apart_need_more_than_shape_similarity():
    a = LineString([(-80.15, 25.75), (-80.149, 25.75)])
    b = LineString([(-80.15, 25.750009), (-80.149, 25.750009)])
    result = merge_features(
        [port(a, kind="quay"), port(b, "osm", "osm", "quay")], BOUNDS
    )
    assert len(result.features) == 2


def test_real_ign_shortbread_port_pairs_merge_without_changing_official_geometry():
    import json
    from pathlib import Path
    from shapely.geometry import shape

    data = json.loads(
        (Path(__file__).parents[1] / "fixtures/marine/port-merge.json").read_text()
    )
    assert len(data["cases"]) == 4
    for case in data["cases"]:
        features = []
        for raw in case["features"]:
            values = {
                **raw,
                "geometry": shape(raw["geometry"]),
                "provenance": tuple(raw["provenance"]),
            }
            features.append(PortInfrastructureFeature(**values))
        result = merge_features(features, data["bounds"])
        assert result.matches == [tuple(case["pair"])]
        assert len(result.features) == 1
        kept = result.features[0]
        assert kept.source == "ign" and kept.geometry.equals(features[0].geometry)
        assert set(kept.provenance) == set(
            features[0].provenance + features[1].provenance
        )
