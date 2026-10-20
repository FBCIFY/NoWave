import asyncio
import json
from pathlib import Path

import httpx
import pytest

from app.domain.marine import MarineFamily
from app.infrastructure.marine.http import MarineHTTP
from app.domain.marine import ProviderUnavailable
from app.infrastructure.marine.normalization import (
    CLASSES,
    attach_topmark,
    infrastructure,
    seamark,
)
from app.infrastructure.marine.providers import NoaaProvider, ShomProvider
from app.domain.marine_tile import Tile


def tile_at(lon, lat, z=12):
    import math

    n = 1 << z
    return Tile(
        z,
        int((lon + 180) / 360 * n),
        int((1 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2 * n),
    )


FIXTURES = Path(__file__).parents[1] / "fixtures/marine"


def test_real_shom_attributes_linked_topmarks_and_cardinal_beacons():
    data = json.loads((FIXTURES / "shom.json").read_text())
    tops = {f["properties"]["inspireid"]: f for f in data["topmar"]}
    for code, kind in CLASSES.items():
        for raw in data.get(code, []):
            mark = seamark(raw, kind, source="shom", dataset=code, priority=100)
            if raw["properties"].get("topmar") in tops:
                mark = attach_topmark(mark, tops[raw["properties"]["topmar"]])
                assert mark.topmark_shape and mark.topmark_color
            assert mark.geometry.x > 5 and mark.geometry.y > 43
            assert mark.navigation_system == "IALA_A"
    assert data["bcncar"] and CLASSES["bcncar"] == "beacon_cardinal"


def test_real_noaa_region_b_and_s57_quay_semantics():
    data = json.loads((FIXTURES / "noaa.json").read_text())
    marks = [
        seamark(f, "buoy_lateral", source="noaa", dataset="harbour:6", priority=105)
        for f in data["buoys"]
    ]
    assert [(f.category, f.color, f.navigation_system) for f in marks] == [
        ("port", "green", "IALA_B"),
        ("starboard", "red", "IALA_B"),
    ]
    for raw in data["ports"]:
        f = infrastructure(
            raw, "construction", source="noaa", dataset="harbour:138", priority=105
        )
        assert f.geometry.geom_type == "Polygon"
        assert f.infrastructure_type != "dock"  # Land construction is not water.


def test_shom_adapter_contract_offline(tmp_path):
    fixture = json.loads((FIXTURES / "shom.json").read_text())
    seen = []

    def handler(request):
        params = request.url.params
        assert params["version"] == "1.0.0" and params["srsName"] == "EPSG:4326"
        code = params["typeName"].split(":")[1]
        seen.append(code)
        return httpx.Response(
            200, json={"type": "FeatureCollection", "features": fixture.get(code, [])}
        )

    async def run():
        http = MarineHTTP(tmp_path / "cache.sqlite", httpx.MockTransport(handler))
        result = await ShomProvider(http).fetch(
            tile_at(5.93, 43.09), MarineFamily.SEAMARKS
        )
        assert not result.failures and result.features
        assert all(f.type.startswith(("buoy_", "beacon_")) for f in result.features)
        assert any(f.topmark_shape for f in result.features)
        await http.close()

    asyncio.run(run())
    assert set(seen) == set(CLASSES) | {"topmar"}


def test_noaa_transfer_limit_is_not_silently_accepted(tmp_path):
    calls = []

    def handler(request):
        calls.append(request.url.params["resultOffset"])
        return httpx.Response(
            200,
            json={
                "type": "FeatureCollection",
                "features": [],
                "exceededTransferLimit": True,
            },
        )

    async def run():
        http = MarineHTTP(tmp_path / "cache.sqlite", httpx.MockTransport(handler))
        with pytest.raises(ProviderUnavailable):
            await NoaaProvider(http)._layer(
                tile_at(-80.15, 25.77), {"scale": "harbour", "layer": 6}
            )
        await http.close()

    asyncio.run(run())
    assert calls == ["0", "1000"]


def test_persistent_osm_cache_and_failed_requests_not_cached(tmp_path):
    calls = []

    def handler(request):
        calls.append(request.url.path)
        return httpx.Response(
            200, content=b"mvt", headers={"Cache-Control": "max-age=900000"}
        )

    path = tmp_path / "http.sqlite"

    async def once():
        http = MarineHTTP(path, httpx.MockTransport(handler))
        assert (
            await http.get("https://example.test/1/0/0.mvt", ttl=604800, osm=True)
            == b"mvt"
        )
        await http.close()

    asyncio.run(once())
    asyncio.run(once())
    assert len(calls) == 1
    import sqlite3, time

    with sqlite3.connect(path) as db:
        expires = db.execute("SELECT expires FROM responses").fetchone()[0]
        assert expires - time.time() > 899900

    def error(_):
        return httpx.Response(503)

    async def fail():
        http = MarineHTTP(tmp_path / "failed.sqlite", httpx.MockTransport(error))
        with pytest.raises(ProviderUnavailable):
            await http.get("https://example.test/2")
        assert http._db().execute("SELECT COUNT(*) FROM responses").fetchone()[0] == 0
        await http.close()

    asyncio.run(fail())


def test_real_ign_3d_geometry_semantic_mapping_and_family_coverage(tmp_path):
    from app.infrastructure.marine.ign import IgnPortProvider

    data = json.loads((FIXTURES / "ign.json").read_text())

    def handler(request):
        assert request.url.params["srsName"] == "urn:ogc:def:crs:OGC:1.3:CRS84"
        assert "nature='Quai'" in request.url.params["cql_filter"]
        assert "bbox" not in request.url.params
        return httpx.Response(200, json=data)

    async def run():
        http = MarineHTTP(tmp_path / "ign.sqlite", httpx.MockTransport(handler))
        p = IgnPortProvider(http)
        tile = tile_at(5.93, 43.09)
        assert p.covers(tile, MarineFamily.PORTS)
        assert not p.covers(tile, MarineFamily.SEAMARKS)
        assert not p.covers(tile_at(166.44, -22.27), MarineFamily.PORTS)
        batch = await p.fetch(tile, MarineFamily.PORTS)
        assert not batch.failures
        assert {f.infrastructure_type for f in batch.features} == {
            "pontoon",
            "breakwater",
            "groyne",
            "jetty",
            "quay",
        }
        assert all(not f.geometry.has_z for f in batch.features)
        assert all(f.source_id.startswith("CONSLINE") for f in batch.features)
        await http.close()

    asyncio.run(run())


def test_bad_vector_payload_cannot_poison_http_cache(tmp_path):
    def handler(_):
        return httpx.Response(200, content=b"<html>upstream failure</html>")

    async def run():
        http = MarineHTTP(tmp_path / "bad.sqlite", httpx.MockTransport(handler))
        with pytest.raises(ProviderUnavailable):
            await http.get("https://tiles.test/1", vector_tile=True)
        assert http._db().execute("SELECT COUNT(*) FROM responses").fetchone()[0] == 0
        await http.close()

    asyncio.run(run())


def test_ign_inland_port_selection_does_not_depend_on_shom_sea_mask():
    from app.infrastructure.marine.ign import IgnPortProvider

    assert IgnPortProvider(None).covers(
        tile_at(-0.57, 44.84), MarineFamily.PORTS
    )  # Bordeaux


def test_real_fallback_mvt_coordinates_types_and_dock_semantics(tmp_path):
    from app.infrastructure.marine.providers import (
        OpenWatersProvider,
        ShortbreadProvider,
    )
    from app.domain.marine_tile import Tile

    def handler(request):
        file = (
            "openwaters.pbf"
            if request.url.host == "tiles.openwaters.io"
            else "shortbread.pbf"
        )
        return httpx.Response(200, content=(FIXTURES / file).read_bytes())

    async def run():
        http = MarineHTTP(tmp_path / "fallback.sqlite", httpx.MockTransport(handler))
        tile = Tile(12, 2115, 1503)
        aids = await OpenWatersProvider(http).fetch(tile, MarineFamily.SEAMARKS)
        assert aids.features and all(f.type.startswith(("buoy_", "beacon_")) for f in aids.features)
        assert {"buoy_lateral", "buoy_safe_water", "buoy_special_purpose"} <= {
            f.type for f in aids.features
        }
        assert all(
            5.88 < f.geometry.x < 5.98 and 43.06 < f.geometry.y < 43.14
            for f in aids.features
        )
        ports = await ShortbreadProvider(http).fetch(tile, MarineFamily.PORTS)
        assert {"dock", "pier", "breakwater", "groyne"} <= {
            f.infrastructure_type for f in ports.features
        }
        assert all(
            f.geometry.geom_type in {"Polygon", "MultiPolygon"}
            for f in ports.features
            if f.infrastructure_type == "dock"
        )
        assert all(
            f.source_id.startswith(("water_polygons:", "pier_lines:", "pier_polygons:"))
            for f in ports.features
        )
        await http.close()

    asyncio.run(run())
