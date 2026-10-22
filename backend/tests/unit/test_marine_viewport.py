import asyncio
import json
from dataclasses import replace

import pytest
from fastapi.testclient import TestClient
from shapely.geometry import LineString, Point, shape
from shapely.ops import unary_union

from app.application.services.marine_tiles import MarineTileService
from app.domain.hydrography import DepthContour
from app.domain.marine import (
    HarbourFeature,
    MarineFamily,
    ProviderBatch,
    ProviderUnavailable,
)
from app.domain.marine_tile import Tile
from app.infrastructure.marine.viewport_encoding import encode_viewport_tile
from app.main import app


def contour(geometry, **kwargs):
    return DepthContour(
        id="emodnet:real-id",
        source="emodnet",
        source_id="real-id",
        source_priority=20,
        geometry=geometry,
        value_m=10,
        derivation="published_dtm_contour_2022",
        **kwargs,
    )


def test_fixed_fragments_preserve_exact_coordinates_depth_and_partition_without_overlap():
    a, b = Tile(12, 2115, 1503), Tile(12, 2116, 1503)
    w, s, e, n = a.bounds
    line = LineString([(w + 0.001, (s + n) / 2), (e + 0.01, (s + n) / 2)])
    f = contour(line, display_minzoom=14)
    fragments = [
        json.loads(encode_viewport_tile(t, MarineFamily.CONTOURS, [f]))["features"][0]
        for t in [a, b]
    ]
    geoms = [shape(f["geometry"]) for f in fragments]
    assert unary_union(geoms).equals(line)
    assert geoms[0].intersection(geoms[1]).length < 1e-12
    assert fragments[0]["id"] != fragments[1]["id"]
    assert all(f["properties"]["id"] == "emodnet:real-id" for f in fragments)
    assert all(f["properties"]["depth_label"] == "10" for f in fragments)
    # Later display levels are present in the Z12 preload, without fabrication.
    assert all(f["properties"]["display_minzoom"] == 14 for f in fragments)


def test_point_half_open_ownership_and_distinct_colocated_identities():
    a, b = Tile(12, 2115, 1503), Tile(12, 2116, 1503)
    _, s, e, n = a.bounds
    f = HarbourFeature(
        id="a",
        source="openwaters-harbours",
        source_id="1",
        source_priority=10,
        geometry=Point(e, (s + n) / 2),
    )
    left = json.loads(encode_viewport_tile(a, MarineFamily.HARBOURS, [f]))["features"]
    right = json.loads(
        encode_viewport_tile(b, MarineFamily.HARBOURS, [f, replace(f, id="b")])
    )["features"]
    assert left == [] and {f["id"] for f in right} == {"a", "b"}


def test_snapshot_and_mvt_caches_are_separate_bounded_and_errors_not_cached():
    class Provider:
        id = "emodnet-contours"
        fail = False
        calls = 0

        def covers(self, *_):
            return True

        async def fetch(self, *_):
            self.calls += 1
            if self.fail:
                raise ProviderUnavailable("offline")
            return ProviderBatch((contour(LineString([(5.9, 43.1), (6, 43.1)])),))

    async def run():
        p = Provider()
        service = MarineTileService([p])
        tile = Tile(12, 2115, 1503)
        raw = await service.get_tile(tile, MarineFamily.CONTOURS, geojson=True)
        assert json.loads(raw.content)["features"]
        assert (
            await service.get_tile(tile, MarineFamily.CONTOURS, geojson=True)
        ) is raw
        mvt = await service.get_tile(tile, MarineFamily.CONTOURS)
        assert mvt.content != raw.content and p.calls == 2
        assert service._bytes == len(raw.content) + len(mvt.content)
        p.fail = True
        with pytest.raises(ProviderUnavailable):
            await service.get_tile(
                Tile(12, 2116, 1503), MarineFamily.CONTOURS, geojson=True
            )
        assert len(service._cache) == 2

    asyncio.run(run())


@pytest.mark.parametrize(
    "path",
    [
        "depth-contours/13/0/0",
        "port-infrastructure/12/0/0",
        "harbours/5/0/0",
        "seamarks/9/0/0",
        "harbours/6/64/0",
    ],
)
def test_invalid_snapshot_rejected_before_network(path):
    assert (
        TestClient(app).get(f"/api/v1/map/marine-features/{path}.geojson").status_code
        == 422
    )


def test_public_snapshot_route_real_service_geometry_and_attribution_link(monkeypatch):
    class Provider:
        id = "emodnet-contours"

        def covers(self, *_):
            return True

        async def fetch(self, *_):
            return ProviderBatch((contour(LineString([(5.9, 43.1), (6, 43.1)])),))

    service = MarineTileService([Provider()])
    monkeypatch.setattr("app.api.routes.map_tiles.get_marine_service", lambda: service)
    response = TestClient(app).get(
        "/api/v1/map/marine-features/depth-contours/12/2115/1503.geojson"
    )
    assert response.status_code == 200
    assert response.headers["content-type"] == "application/geo+json"
    assert response.json()["features"]
    assert "marine-sources" in response.headers["link"]


def test_line_exactly_on_cell_edge_is_owned_once():
    import math

    a, b = Tile(12, 2115, 1503), Tile(12, 2116, 1503)
    edge = (a.x + 1) / (1 << a.z) * 360 - 180
    north = math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * a.y / (1 << a.z)))))
    south = math.degrees(
        math.atan(math.sinh(math.pi * (1 - 2 * (a.y + 1) / (1 << a.z))))
    )
    f = contour(LineString([(edge, south + 0.001), (edge, north - 0.001)]))
    left = json.loads(encode_viewport_tile(a, MarineFamily.CONTOURS, [f]))["features"]
    right = json.loads(encode_viewport_tile(b, MarineFamily.CONTOURS, [f]))["features"]
    assert not left and len(right) == 1
    assert shape(right[0]["geometry"]).equals(f.geometry)


def test_cancelling_provider_collection_stops_queued_work():
    from app.infrastructure.marine.providers import collect

    async def run():
        started = asyncio.Event()
        stopped = asyncio.Event()

        async def job():
            started.set()
            try:
                await asyncio.Event().wait()
            finally:
                stopped.set()

        work = asyncio.create_task(collect([("public-source", job())]))
        await started.wait()
        work.cancel()
        with pytest.raises(asyncio.CancelledError):
            await work
        assert stopped.is_set()

    asyncio.run(run())


def test_original_sounding_resolution_z16_is_available_without_opening_other_families(
    monkeypatch,
):
    from app.application.services.marine_tiles import MarineTileResult

    calls = []

    class Service:
        async def get_tile(self, tile, family, **kwargs):
            calls.append((tile, family))
            return MarineTileResult(
                b'{"type":"FeatureCollection","features":[]}', status="outside-coverage"
            )

    monkeypatch.setattr(
        "app.api.routes.map_tiles.get_marine_service", lambda: Service()
    )
    client = TestClient(app)
    assert (
        client.get(
            "/api/v1/map/marine-features/soundings/16/33845/24060.geojson"
        ).status_code
        == 200
    )
    assert calls[0][0].z == 16
    for family in ["harbours", "seamarks", "underwater-hazards"]:
        assert (
            client.get(
                f"/api/v1/map/marine-features/{family}/16/33845/24060.geojson"
            ).status_code
            == 422
        )
    assert len(calls) == 1
