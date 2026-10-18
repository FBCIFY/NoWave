"""Synthetic edge cases are explicit; live excerpts have their own provenance."""

import asyncio
from dataclasses import replace
import json

import mapbox_vector_tile
import pytest
from shapely.geometry import (
    LineString,
    MultiLineString,
    MultiPoint,
    MultiPolygon,
    Point,
    mapping,
    box,
)

from app.application.services.marine_merge import merge_features
from app.application.services.marine_tiles import MarineTileService
from app.domain.hydrography import DepthContour, Sounding, UnderwaterHazard
from app.domain.marine import MarineFamily, ProviderBatch, ProviderUnavailable
from app.domain.marine_tile import Tile
from app.infrastructure.marine.encoding import clip_geometry, encode_tile
from app.infrastructure.marine.hydro_normalization import (
    normalize_hydro,
    depth_values,
    select_soundings,
)
from app.infrastructure.marine.hydro_providers import (
    ShomHazardProvider,
    NoaaHydroProvider,
)


def raw(geometry=None, **props):
    return dict(
        id="test-1",
        type="Feature",
        geometry=mapping(geometry if geometry is not None else Point(5.93, 43.08)),
        properties=props,
    )


def normalized(kind, geometry=None, **props):
    return normalize_hydro(raw(geometry, **props), kind, source="noaa", dataset="test")


@pytest.mark.parametrize("unit,value", [("m", 10), ("ft", 3.048), ("fathom", 18.288)])
def test_explicit_units_retain_original_and_sign(unit, value):
    values = depth_values(-10, unit)
    assert values == dict(value_original=-10.0, unit_original=unit, value_m=-value)


def test_unknown_units_and_missing_depth_never_create_values():
    with pytest.raises(ValueError):
        depth_values(12, "unknown")
    assert depth_values(None, "m")["value_m"] is None
    for kind, geometry in [
        ("depth_contour", LineString([(5.9, 43), (6, 43)])),
        ("sounding", Point(5.9, 43)),
    ]:
        with pytest.raises(ValueError):
            normalized(kind, geometry)
    hazard = normalized("wreck", HEIGHT=12)[0]
    assert hazard.value_m is None and hazard.least_depth is None
    assert json.loads(hazard.source_attributes)["HEIGHT"] == 12


@pytest.mark.parametrize(
    "geometry,expected",
    [
        (MultiPoint([(5.9, 43, 2.2), (5.91, 43.01, -0.3)]), [2.2, -0.3]),
        (MultiPoint([(5.9, 43), (5.91, 43.01)]), [2.2, -0.3]),
    ],
)
def test_multipoint_preserves_each_coordinate_depth_pair(geometry, expected):
    features = normalized("sounding", geometry, depths=expected, Z=99)
    assert [(f.geometry.x, f.geometry.y, f.value_m) for f in features] == [
        (5.9, 43, 2.2),
        (5.91, 43.01, -0.3),
    ]
    assert [f.sample_index for f in features] == [0, 1]
    assert len({f.id for f in features}) == 2
    assert all(f.source_geometry_type == "MultiPoint" for f in features)


@pytest.mark.parametrize("props", [{}, {"Z": 4}, {"depths": [4]}])
def test_ambiguous_multipoint_is_rejected(props):
    with pytest.raises(ValueError):
        normalized("sounding", MultiPoint([(5.9, 43), (5.91, 43.01)]), **props)


def test_published_datum_quality_and_negative_depth_preserved():
    f = normalized(
        "wreck", VALSOU=-1.2, VERDAT=23, QUASOU="6", SOUACC=0.5, WATLEV=4, CATWRK="2"
    )[0]
    assert (
        f.value_m,
        f.vertical_datum,
        f.sounding_datum,
        f.quality,
        f.accuracy,
        f.water_level,
        f.category,
    ) == (-1.2, "23", None, "6", 0.5, "covers_and_uncovers", "2")
    assert normalized("rock")[0].vertical_datum is None


@pytest.mark.parametrize("kind", ["rock", "wreck", "obstruction"])
@pytest.mark.parametrize(
    "geometry",
    [
        Point(5.93, 43.08),
        MultiPoint([(5.93, 43.08), (5.94, 43.08)]),
        LineString([(5.92, 43.08), (5.94, 43.08)]),
        MultiLineString([[(5.92, 43.08), (5.94, 43.08)]]),
        box(5.92, 43.07, 5.94, 43.09),
        MultiPolygon([box(5.92, 43.07, 5.94, 43.09)]),
    ],
)
def test_hazard_families_and_geometries_remain_distinct(kind, geometry):
    f = normalized(kind, geometry, VALSOU=3.2)[0]
    assert isinstance(f, UnderwaterHazard) and f.hazard_type == kind
    assert f.geometry.equals(geometry)
    layer = mapbox_vector_tile.decode(
        encode_tile(Tile(12, 2115, 1503), MarineFamily.HAZARDS, [f])
    )["underwater_hazard"]
    assert len(layer["features"]) == 1
    assert layer["features"][0]["properties"]["hazard_type"] == kind


def test_contour_lines_and_actual_depths_are_not_soundings():
    geom = MultiLineString([[(5.92, 43.08), (5.94, 43.08)]])
    f = normalized("depth_contour", geom, VALDCO=7.3)[0]
    assert (
        isinstance(f, DepthContour) and f.value_m == 7.3 and f.contour_class == "minor"
    )
    assert isinstance(normalized("sounding", Z=7.3)[0], Sounding)
    with pytest.raises(ValueError):
        normalized("depth_contour", Point(5.9, 43), VALDCO=20)


def test_published_emodnet_contour_is_explicitly_derived_not_enc():
    f = normalize_hydro(
        raw(LineString([(5.92, 43.08), (5.94, 43.08)]), elevation=50),
        "depth_contour",
        source="emodnet",
        dataset="contours-2022",
    )[0]
    assert f.derivation == "published_dtm_contour_2022" and f.value_m == 50
    assert f.vertical_datum is None and f.sounding_datum is None


def test_shom_qualified_brassiage_is_not_fabricated_minimum():
    f = normalize_hydro(
        raw(
            brassiage=15,
            precis_bra="brassiage inconnu mais estimé supérieur au brassiage indiqué",
            precis_loc=20,
        ),
        "wreck",
        source="shom",
        dataset="wrecks",
    )[0]
    assert f.value_m == 15 and f.least_depth is None and f.horizontal_accuracy == 20
    assert f.vertical_datum is None
    assert f.sounding_datum == "chart_datum" and f.datum_reference.endswith(
        "spec_epaves_et_obstructions.pdf"
    )


def test_conservative_merge_requires_identity_attributes_geometry_and_datum():
    a = normalized("wreck", VALSOU=5)[0]
    assert len(merge_features([a, replace(a)], (5, 42, 7, 44)).features) == 1
    for b in [
        replace(a, id="other", source_id="other"),
        replace(a, vertical_datum="LAT"),
        replace(a, hazard_type="rock"),
        replace(a, value_m=6),
        replace(a, geometry=Point(5.93001, 43.08)),
        replace(a, category="2"),
    ]:
        assert len(merge_features([a, b], (5, 42, 7, 44)).features) == 2


def test_zoom_thresholds_are_backend_contract_and_no_upstream_below_threshold():
    class Provider:
        id = "test"
        calls = 0

        def covers(self, *args):
            return True

        async def fetch(self, *args):
            self.calls += 1
            return ProviderBatch()

    async def run():
        p = Provider()
        svc = MarineTileService([p])
        for family, z, name in [
            (MarineFamily.CONTOURS, 11, "depth_contour"),
            (MarineFamily.SOUNDINGS, 11, "sounding"),
            (MarineFamily.HAZARDS, 11, "underwater_hazard"),
        ]:
            result = await svc.get_tile(Tile(z, 0, 0), family)
            assert mapbox_vector_tile.decode(result.content)[name]["features"] == []
        assert p.calls == 0
        await svc.get_tile(Tile(12, 0, 0), MarineFamily.CONTOURS)
        assert p.calls == 1

    asyncio.run(run())


def test_major_minor_selection_uses_only_published_depths():
    fs = [
        normalized(
            "depth_contour", LineString([(5.92, 43.08), (5.94, 43.08)]), VALDCO=d
        )[0]
        for d in [0.7, 1.8, 3.6, 20]
    ]
    for z, expected in [
        (11, []),
        (12, [3.6, 20]),
        (13, [1.8, 3.6, 20]),
        (14, [0.7, 1.8, 3.6, 20]),
    ]:
        base = Tile(14, 8461, 6015).parent(z)
        decoded = mapbox_vector_tile.decode(
            encode_tile(base, MarineFamily.CONTOURS, fs)
        )["depth_contour"]
        assert [f["properties"]["value_m"] for f in decoded["features"]] == expected


def test_sounding_density_is_nested_deterministic_and_keeps_shallowest():
    fs = [
        replace(
            normalized(
                "sounding",
                Point(5.93 + i * 0.00004, 43.08 + j * 0.00004),
                Z=(i + j + 1),
            )[0],
            id=f"{i}-{j}",
            source_id=f"{i}-{j}",
        )
        for i in range(15)
        for j in range(15)
    ]
    sets = []
    for z in (14, 15, 16):
        selected = select_soundings(fs, z)
        assert selected == select_soundings(list(reversed(fs)), z)
        assert any(f.value_m == 1 for f in selected)
        sets.append({f.id for f in selected})
    assert sets[0] <= sets[1] <= sets[2]
    assert len(sets[0]) < len(sets[2]) < len(fs)
    # Incompatible references are never ordered as equivalent depth observations.
    assert (
        len(
            select_soundings(
                [fs[0], replace(fs[0], id="other-datum", vertical_datum="MSL")], 14
            )
        )
        == 2
    )


def test_local_chart_density_exceeds_offshore_and_unknown_cells_stay_separate():
    samples = [
        replace(
            normalized(
                "sounding", Point(5.93 + i * 0.0005, 43.08 + j * 0.0005), Z=i + j + 1
            )[0],
            id=f"{i}-{j}",
            source_id=f"test:{i}-{j}",
        )
        for i in range(30)
        for j in range(30)
    ]
    for zoom in (14, 15, 16):
        local = select_soundings([replace(f, scale="harbour") for f in samples], zoom)
        offshore = select_soundings(
            [replace(f, scale="coastal") for f in samples], zoom
        )
        assert len(local) > len(offshore)
        assert min(f.value_m for f in local) == 1
    a = samples[0]
    b = replace(a, id="other", source_id="different:0", value_m=100)
    assert len(select_soundings([a, b], 14)) == 2


@pytest.mark.parametrize(
    "kind,geometry,props,value",
    [
        (
            "depth_contour",
            LineString([(5.92, 43.08), (5.94, 43.08)]),
            {"VALDCO": 3.6},
            "3.6",
        ),
        ("sounding", Point(5.93, 43.08), {"Z": 1.25}, "1.25"),
        ("sounding", Point(5.93, 43.08), {"Z": -0.3}, "-0.3"),
    ],
)
def test_encoded_labels_preserve_real_depth_and_decimals(kind, geometry, props, value):
    f = normalized(kind, geometry, **props)[0]
    family = (
        MarineFamily.CONTOURS if kind == "depth_contour" else MarineFamily.SOUNDINGS
    )
    tile = Tile(12, 2115, 1503) if kind == "depth_contour" else Tile(14, 8461, 6015)
    # Derive the tile from the coordinate to keep the test independent of fixtures.
    from app.domain.marine_tile import project, HALF_WORLD

    x, y = project(5.93, 43.08)
    tile = Tile(
        tile.z,
        int((x + HALF_WORLD) / (2 * HALF_WORLD) * 2**tile.z),
        int((HALF_WORLD - y) / (2 * HALF_WORLD) * 2**tile.z),
    )
    decoded = mapbox_vector_tile.decode(encode_tile(tile, family, [f]))[kind][
        "features"
    ]
    assert decoded[0]["properties"]["depth_label"] == value


def test_official_shom_xyz_samples_have_provenance_datum_and_no_invented_accuracy():
    from app.infrastructure.marine.shom_soundings import (
        survey_soundings,
        ShomSoundingProvider,
    )

    samples = survey_soundings()
    assert len(samples) == 7795
    sample = next(f for f in samples if f.source_id == "S200806500:4")
    assert (sample.geometry.x, sample.geometry.y, sample.value_m) == (
        5.9274025,
        43.1013295,
        2.8,
    )
    assert sample.vertical_datum == sample.sounding_datum == "LAT"
    assert sample.unit_original == "m" and sample.license == "etalab-2.0"
    assert sample.accuracy is sample.horizontal_accuracy is None
    assert sample.source_date == "2008-09-09"
    assert sample.provenance[0].endswith("S200806500")
    assert json.loads(sample.source_attributes)["xyz"] == "5.9274025,43.1013295,2.8"
    selected = next(f for f in samples if f.source_id == "S201300200:99213641")
    assert selected.value_m == 0.26
    assert selected.geometry.equals(Point(5.9288793, 43.1178259))
    assert selected.source_date == "2013-07-12"
    assert all(f.value_m >= 0 for f in samples if f.source_id.startswith("S201300200:"))
    provider = ShomSoundingProvider()
    assert not provider.covers(Tile(12, 2115, 1503), MarineFamily.HAZARDS)


def test_offline_survey_import_retains_original_minimum_rows_without_interpolation(
    tmp_path,
):
    from backend.tools.import_shom_survey import select_rows

    path = tmp_path / "synthetic.xyz"
    # Explicit synthetic import edge case, not a runtime geographic fixture.
    path.write_text(
        "Shom test\nTEST\nlong(DD),lat(DD),depth(m - down positive - LAT)\n"
        "5.93,43.08,15\n5.93000001,43.08000001,1.25\n"
        "5.93000002,43.08000002,1.25\n6.5,43.08,0.1\n"
    )
    header, total, inside, rows = select_rows(path, [5.9, 43, 6, 43.1])
    assert total == 4 and inside == 3
    assert rows == [(1.25, 5, "5.93000001,43.08000001,1.25")]
    with path.open("a") as stream:
        stream.write("5.93000001,43.08000001,-8.3\n")
    assert select_rows(path, [5.9, 43, 6, 43.1])[3][0][0] == -8.3
    assert select_rows(path, [5.9, 43, 6, 43.1], minimum_depth=0)[3][0][0] == 1.25
    path.write_text("Bad\nTEST\nunknown unit and datum\n")
    with pytest.raises(ValueError, match="unit/datum"):
        select_rows(path, [5.9, 43, 6, 43.1])


def test_clipping_and_simplification_bound_error_and_keep_tile_edges():
    tile = Tile(12, 2115, 1503)
    w, s, e, n = tile.bounds
    f = normalized(
        "depth_contour",
        LineString(
            [(w - 0.01, s + 0.01), (w + 0.001, s + 0.010001), (e + 0.01, s + 0.01)]
        ),
        VALDCO=20,
    )[0]
    layer = mapbox_vector_tile.decode(encode_tile(tile, MarineFamily.CONTOURS, [f]))[
        "depth_contour"
    ]
    assert layer["extent"] == 4096
    coordinates = layer["features"][0]["geometry"]["coordinates"]
    assert (
        min(x for x, y in coordinates) >= -64 and max(x for x, y in coordinates) <= 4160
    )
    assert len(coordinates) <= 3
    assert clip_geometry(MultiPoint([(0, 0), (2, 2)]), box(-1, -1, 1, 1)).equals(
        Point(0, 0)
    )


def test_provider_failure_not_cached_and_success_is_single_flight_cached():
    class Provider:
        id = "official"
        fail = True
        calls = 0

        def covers(self, *args):
            return True

        async def fetch(self, *args):
            self.calls += 1
            if self.fail:
                raise ProviderUnavailable("offline")
            return ProviderBatch(tuple(normalized("wreck", VALSOU=4)))

    async def run():
        p = Provider()
        svc = MarineTileService([p])
        t = Tile(12, 2115, 1503)
        with pytest.raises(ProviderUnavailable):
            await svc.get_tile(t, MarineFamily.HAZARDS)
        p.fail = False
        results = await asyncio.gather(
            *(svc.get_tile(t, MarineFamily.HAZARDS) for _ in range(3))
        )
        assert p.calls == 2 and all(r.content == results[0].content for r in results)

    asyncio.run(run())


def test_shom_requests_explicit_bbox_crs_and_keeps_source_qualifications():
    class Http:
        async def get(self, url, params):
            assert params["bbox"].endswith(",EPSG:4326")
            return json.dumps(
                dict(
                    type="FeatureCollection",
                    features=[raw(brassiage=3.5, precis_bra="brassiage minimal connu")],
                    numberMatched=1,
                )
            ).encode()

    result = asyncio.run(
        ShomHazardProvider(Http()).fetch(Tile(12, 2115, 1503), MarineFamily.HAZARDS)
    )
    assert not result.failures and {f.hazard_type for f in result.features} == {
        "wreck",
        "obstruction",
    }


def test_noaa_uses_real_scale_coverage_and_requests_per_vertex_z(monkeypatch):
    import app.infrastructure.marine.hydro_providers as module

    monkeypatch.setattr(
        module,
        "LAYERS",
        [
            dict(
                kind="sounding",
                rank=5,
                scale="harbour",
                layer=76,
                bounds=[-180, -80, 180, 80],
            )
        ],
    )
    calls = []

    class Http:
        async def get(self, url, params):
            calls.append((url, params))
            if "enc_coverage" in url:
                assert "orderByFields" not in params
                features = [raw(box(5.8, 43, 6, 43.2))] if "/4/query" in url else []
            else:
                assert params["returnZ"] == "true"
                features = [raw(Point(5.93, 43.08, 2.5), Z=2.5)]
            return json.dumps(
                dict(type="FeatureCollection", features=features)
            ).encode()

    result = asyncio.run(
        NoaaHydroProvider(Http()).fetch(Tile(14, 8461, 6015), MarineFamily.SOUNDINGS)
    )
    assert (
        not result.failures
        and len(result.features) == 1
        and result.features[0].value_m == 2.5
    )
    assert len(calls) == 6


def test_real_public_excerpts_normalize_all_families_without_losing_source_values():
    from pathlib import Path

    data = json.loads(
        (
            Path(__file__).parents[1] / "fixtures/marine/hydrography-real.json"
        ).read_text()
    )
    kinds = set()
    for example in data["examples"]:
        f = example["feature"]
        source = example["source"]
        kind = example["kind"]
        result = normalize_hydro(f, kind, source=source, dataset="real-excerpt")
        assert result and all(
            r.source_attributes
            == json.dumps(f["properties"], sort_keys=True, separators=(",", ":"))
            for r in result
        )
        assert result[0].source_geometry_type == f["geometry"]["type"]
        kinds.add(kind)
    assert kinds == {"depth_contour", "sounding", "rock", "wreck", "obstruction"}


def test_noaa_excludes_no_coverage_cells_and_keeps_coarser_coverage(monkeypatch):
    import app.infrastructure.marine.hydro_providers as module

    monkeypatch.setattr(
        module,
        "LAYERS",
        [
            dict(
                kind="sounding", rank=r, scale=s, layer=76, bounds=[-180, -80, 180, 80]
            )
            for r, s in [(4, "approach"), (5, "harbour")]
        ],
    )
    queried = []

    class Http:
        async def get(self, url, params):
            if "enc_coverage" in url:
                if "/4/query" in url:
                    features = [
                        raw(box(5.8, 43, 6, 43.2), CATCOV="no coverage available")
                    ]
                elif "/3/query" in url:
                    features = [raw(box(5.8, 43, 6, 43.2), CATCOV="coverage available")]
                else:
                    features = []
            else:
                queried.append(url)
                features = [raw(Z=3.2)]
            return json.dumps(
                dict(type="FeatureCollection", features=features)
            ).encode()

    result = asyncio.run(
        NoaaHydroProvider(Http()).fetch(Tile(14, 8461, 6015), MarineFamily.SOUNDINGS)
    )
    assert not result.failures and len(result.features) == 1
    assert result.features[0].scale == "approach"
    assert all("enc_approach" in url for url in queried)


def test_point_z_transport_noise_is_not_an_invented_precision():
    f = normalized("sounding", Point(5.93, 43.08, 0.899999999994), Z=0.9)[0]
    assert f.value_original == 0.9
    with pytest.raises(ValueError):
        normalized("sounding", Point(5.93, 43.08, 5), Z=0.9)


def test_datum_area_join_requires_same_cell_scale_and_complete_geometry(monkeypatch):
    import app.infrastructure.marine.hydro_providers as module

    monkeypatch.setattr(
        module,
        "LAYERS",
        [
            dict(kind=k, rank=5, scale="harbour", layer=l, bounds=[-180, -80, 180, 80])
            for k, l in [("sounding", 76), ("sounding_datum", 224)]
        ],
    )

    class Http:
        wrong_cell = False

        async def get(self, url, params):
            if "enc_coverage" in url:
                features = (
                    [raw(box(5.8, 43, 6, 43.2), CATCOV=1)] if "/4/query" in url else []
                )
            elif "/224/" in url:
                features = [
                    raw(
                        box(5.8, 43, 6, 43.2),
                        DSNM="other" if self.wrong_cell else "cell",
                        VERDAT=12,
                    )
                ]
            else:
                features = [raw(Z=3.2, DSNM="cell")]
            return json.dumps(
                dict(type="FeatureCollection", features=features)
            ).encode()

    http = Http()
    provider = NoaaHydroProvider(http)
    result = asyncio.run(provider.fetch(Tile(14, 8461, 6015), MarineFamily.SOUNDINGS))
    f = result.features[0]
    assert f.vertical_datum == "12" and f.sounding_datum == "12"
    assert any("harbour:224:" in p for p in f.provenance)
    http.wrong_cell = True
    result = asyncio.run(provider.fetch(Tile(14, 8461, 6015), MarineFamily.SOUNDINGS))
    assert result.features[0].vertical_datum is None
