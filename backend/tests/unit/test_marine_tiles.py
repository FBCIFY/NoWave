import asyncio
from dataclasses import replace

import mapbox_vector_tile
import pytest
from shapely.geometry import LineString, MultiPolygon, Point, Polygon

from app.application.services.marine_tiles import MarineTileService
from app.domain.marine import (
    MarineFamily,
    ProviderBatch,
    SeamarkFeature,
    PortInfrastructureFeature,
)
from app.infrastructure.marine.encoding import encode_tile
from app.domain.marine_tile import Tile
from app.domain.marine import ProviderUnavailable
from app.infrastructure.marine.providers import (
    ShomProvider,
    NoaaProvider,
    ShortbreadProvider,
    OpenWatersProvider,
)


def tile_at(lon, lat, z=12):
    import math

    n = 1 << z
    return Tile(
        z,
        int((lon + 180) / 360 * n),
        int((1 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2 * n),
    )


@pytest.mark.parametrize(
    "lon,lat,expected",
    [
        (5.93, 43.09, {"shom", "openwaters"}),
        (-80.15, 25.77, {"noaa", "openwaters"}),
        (
            -123.1,
            49.3,
            {"noaa", "openwaters"},
        ),  # NOAA chart footprints extend over this border.
        (151.22, -33.85, {"openwaters"}),
        (174.77, -36.84, {"openwaters"}),
        (14, 35, {"openwaters"}),
        (-61.55, 16.22, {"shom", "openwaters"}),
        (166.44, -22.27, {"shom", "openwaters"}),
    ],
)
def test_selection_uses_requested_tile_and_actual_integrated_coverage(
    lon, lat, expected
):
    providers = [
        ShomProvider(None),
        NoaaProvider(None),
        ShortbreadProvider(None),
        OpenWatersProvider(None),
    ]
    service = MarineTileService(providers)
    assert {
        p.id for p in service.select(tile_at(lon, lat), MarineFamily.SEAMARKS)
    } == expected
    # There is no user position input anywhere in the selection contract.
    assert all(
        p.id != "shom" for p in service.select(tile_at(lon, lat), MarineFamily.PORTS)
    )


def test_cross_coverage_tile_can_select_multiple_official_providers():
    # Low zoom tile crosses the actual SHOM / NOAA routing masks.
    svc = MarineTileService(
        [ShomProvider(None), NoaaProvider(None), OpenWatersProvider(None)]
    )
    ids = {p.id for p in svc.select(Tile(0, 0, 0), MarineFamily.SEAMARKS)}
    assert ids == {"shom", "noaa", "openwaters"}


class FakeProvider:
    def __init__(self, id, features=(), fail=False):
        self.id, self.features, self.fail, self.calls = id, features, fail, 0

    def covers(self, tile, family):
        return True

    async def fetch(self, tile, family):
        self.calls += 1
        if self.fail:
            raise ProviderUnavailable("offline")
        return ProviderBatch(self.features)


def mark(source="openwaters"):
    return SeamarkFeature(
        id=source,
        source=source,
        source_id=source,
        source_priority=10,
        geometry=Point(5.93, 43.09),
        type="buoy_lateral",
        category="port",
        color="red",
        shape="pillar",
    )


def test_national_outage_fallback_and_recovery_no_negative_success_cache():
    async def run():
        t = tile_at(5.93, 43.09)
        fallback = FakeProvider("openwaters", (mark(),))
        official = FakeProvider("shom", fail=True)
        service = MarineTileService([fallback, official])
        result = await service.get_tile(t, MarineFamily.SEAMARKS)
        assert result.failures
        assert (
            len(mapbox_vector_tile.decode(result.content)["seamark"]["features"]) == 1
        )
        official.fail = False
        official.features = (replace(mark("shom"), source_priority=100),)
        service._cache.clear()
        service._bytes = 0  # Simulate degraded TTL expiry.
        recovered = await service.get_tile(t, MarineFamily.SEAMARKS)
        features = mapbox_vector_tile.decode(recovered.content)["seamark"]["features"]
        assert len(features) == 1 and features[0]["properties"]["source"] == "shom"

    asyncio.run(run())


def test_all_upstreams_down_returns_error_instead_of_empty_success():
    async def run():
        svc = MarineTileService([FakeProvider("openwaters", fail=True)])
        with pytest.raises(ProviderUnavailable):
            await svc.get_tile(tile_at(5.93, 43.09), MarineFamily.SEAMARKS)

    asyncio.run(run())


def test_cache_single_flight_and_low_zoom_avoids_all_upstreams():
    async def run():
        provider = FakeProvider("openwaters", (mark(),))
        svc = MarineTileService([provider])
        t = tile_at(5.93, 43.09)
        results = await asyncio.gather(
            *(svc.get_tile(t, MarineFamily.SEAMARKS) for _ in range(10))
        )
        assert provider.calls == 1 and len({r.content for r in results}) == 1
        await svc.get_tile(Tile(0, 0, 0), MarineFamily.SEAMARKS)
        assert provider.calls == 1

    asyncio.run(run())


@pytest.mark.parametrize("multi", [False, True])
def test_mvt_port_contract_and_geometries(multi):
    t = tile_at(5.93, 43.09)
    polygon = Polygon(
        [(5.93, 43.09), (5.931, 43.09), (5.931, 43.0901), (5.93, 43.0901)]
    )
    polygon = MultiPolygon([polygon]) if multi else polygon
    features = [
        PortInfrastructureFeature(
            id="quay",
            source="noaa",
            source_id="real-quay",
            source_priority=100,
            geometry=polygon,
            infrastructure_type="quay",
            provenance=("noaa:real-quay",),
        )
    ]
    for kind in ["breakwater", "groyne", "pier"]:
        features.append(
            PortInfrastructureFeature(
                id=kind,
                source="osm",
                source_id=kind,
                source_priority=10,
                geometry=LineString([(5.93, 43.09), (5.931, 43.0901)]),
                infrastructure_type=kind,
            )
        )
    layers = mapbox_vector_tile.decode(encode_tile(t, MarineFamily.PORTS, features))
    assert len(layers["port_infrastructure"]["features"]) == 4
    assert {f["properties"]["kind"] for f in layers["pier_lines"]["features"]} == {
        "breakwater",
        "groyne",
        "pier",
    }
    quay = layers["pier_polygons"]["features"][0]
    assert quay["properties"]["infrastructure_type"] == "quay"
    assert quay["geometry"]["type"] in {"Polygon", "MultiPolygon"}


def test_mvt_buoy_properties_and_coordinate_orientation():
    t = tile_at(5.93, 43.09)
    a = mark()
    b = replace(
        a,
        id="north",
        geometry=Point(5.93, 43.095),
        navigation_system="IALA_B",
        topmark_color="red",
    )
    features = mapbox_vector_tile.decode(encode_tile(t, MarineFamily.SEAMARKS, [a, b]))[
        "seamark"
    ]["features"]
    assert (
        features[1]["geometry"]["coordinates"][1]
        > features[0]["geometry"]["coordinates"][1]
    )  # Decoder y-up.
    assert set(
        [
            "id",
            "type",
            "category",
            "color",
            "color_pattern",
            "shape",
            "topmark_shape",
            "topmark_color",
            "name",
            "navigation_system",
            "source",
            "source_id",
            "source_priority",
            "provenance",
        ]
    ) <= set(features[0]["properties"])
    assert features[1]["properties"]["navigation_system"] == "IALA_B"


def test_ports_survive_official_outage_with_osm_line_and_polygon():
    async def run():
        tile = tile_at(5.93, 43.09)
        features = tuple(
            PortInfrastructureFeature(
                id=str(i),
                source="osm",
                source_id=str(i),
                source_priority=10,
                geometry=g,
                infrastructure_type=k,
            )
            for i, (g, k) in enumerate(
                [
                    (LineString([(5.93, 43.09), (5.931, 43.09)]), "breakwater"),
                    (
                        Polygon(
                            [
                                (5.93, 43.09),
                                (5.931, 43.09),
                                (5.931, 43.0901),
                                (5.93, 43.0901),
                            ]
                        ),
                        "pier",
                    ),
                ]
            )
        )
        svc = MarineTileService(
            [FakeProvider("osm", features), FakeProvider("ign", fail=True)]
        )
        result = await svc.get_tile(tile, MarineFamily.PORTS)
        layers = mapbox_vector_tile.decode(result.content)
        assert result.failures and result.sources == ("osm",)
        assert len(layers["pier_lines"]["features"]) == 1
        assert len(layers["pier_polygons"]["features"]) == 1

    asyncio.run(run())


def test_mvt_clip_keeps_structures_when_tangencies_create_geometry_collections(
    monkeypatch,
):
    from types import SimpleNamespace
    from shapely.geometry import MultiLineString
    from app.infrastructure.marine import encoding

    # Isolate clipping in tile coordinates. The detached contact point must not
    # make the MVT encoder reject an otherwise valid quay or breakwater.
    monkeypatch.setattr(encoding, "project", lambda x, y: (x, y))
    tile = SimpleNamespace(mercator_bounds=(0, 0, 10, 10))
    left = -10 * 64 / 4096
    polygon = Polygon(
        [(-2, 1), (2, 1), (2, 2), (-1, 2), (-1, 4), (left, 5), (-1, 6), (-2, 6)]
    )
    line = MultiLineString([[(1, 1), (2, 2)], [(-1, 6), (left, 5)]])
    features = [
        PortInfrastructureFeature(
            id=str(i),
            source="noaa",
            source_id=str(i),
            source_priority=100,
            geometry=geometry,
            infrastructure_type=kind,
        )
        for i, (geometry, kind) in enumerate([(polygon, "quay"), (line, "breakwater")])
    ]
    layers = mapbox_vector_tile.decode(encode_tile(tile, MarineFamily.PORTS, features))
    canonical = layers["port_infrastructure"]["features"]
    assert len(canonical) == 2
    assert {f["geometry"]["type"] for f in canonical} == {"Polygon", "LineString"}
    assert len(layers["pier_polygons"]["features"]) == 1
    assert len(layers["pier_lines"]["features"]) == 1


def test_real_quay_line_is_rendered_without_moving_geometry_or_inventing_port():
    quay = PortInfrastructureFeature(
        id="ign:quay", source="ign", source_id="quay", source_priority=100,
        infrastructure_type="quay", geometry=LineString([(5.93, 43.09), (5.931, 43.091)]),
    )
    layers = mapbox_vector_tile.decode(encode_tile(tile_at(5.93, 43.09), MarineFamily.PORTS, [quay]))
    infrastructure = layers["port_infrastructure"]["features"][0]
    rendered = layers["pier_lines"]["features"][0]
    assert rendered["properties"]["kind"] == "quay"
    assert rendered["geometry"] == infrastructure["geometry"]
    assert "harbour" not in layers
