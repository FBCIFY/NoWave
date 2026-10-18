"""USA restoration is geographic and does not reintroduce disk depth storage."""

import asyncio
import json
import sqlite3

import httpx
import mapbox_vector_tile
import pytest
from shapely.geometry import Point

from app.application.services.marine_tiles import MarineTileService
from app.domain.hydrography import Sounding
from app.domain.marine import MarineFamily, ProviderBatch, ProviderUnavailable
from app.infrastructure.marine.http import MarineHTTP
from app.infrastructure.marine.hydro_providers import (
    NoaaSoundingProvider,
    NoaaHydroProvider,
)
from backend.tests.unit.test_marine_tiles import tile_at

FAMILY = MarineFamily.SOUNDINGS


@pytest.mark.parametrize("status", [200, 500])
def test_numeric_http_never_opens_database_or_creates_files(
    monkeypatch, tmp_path, status
):
    def forbidden(*args, **kwargs):
        raise AssertionError("persistent numeric storage")

    monkeypatch.setattr(sqlite3, "connect", forbidden)
    calls = 0

    def handler(request):
        nonlocal calls
        calls += 1
        return httpx.Response(
            status, json={"type": "FeatureCollection", "features": []}
        )

    async def run():
        http = MarineHTTP(
            tmp_path / "unused.sqlite3",
            httpx.MockTransport(handler),
            persistent_cache=False,
        )
        monkeypatch.setattr(http, "_db", forbidden)
        try:
            for _ in range(2):
                if status == 200:
                    assert (
                        json.loads(
                            await http.get(
                                "https://example.test/query", params={"f": "geojson"}
                            )
                        )["features"]
                        == []
                    )
                else:
                    with pytest.raises(ProviderUnavailable):
                        await http.get(
                            "https://example.test/query", params={"f": "geojson"}
                        )
            assert http._database is None and calls == 2
            assert list(tmp_path.iterdir()) == []
        finally:
            await http.close()

    asyncio.run(run())


def test_nonpersistent_mode_cannot_bypass_osm_caching():
    async def run():
        http = MarineHTTP(
            transport=httpx.MockTransport(lambda _: pytest.fail("network")),
            persistent_cache=False,
        )
        try:
            with pytest.raises(ProviderUnavailable, match="OSM requires"):
                await http.get("https://example.test/tile", osm=True)
        finally:
            await http.close()

    asyncio.run(run())


def test_noaa_restored_only_in_chart_coverage_from_z14(monkeypatch):
    calls = []

    async def fetch(self, tile, family):
        calls.append((tile, family))
        return ProviderBatch()

    monkeypatch.setattr(NoaaHydroProvider, "fetch", fetch)
    p = NoaaSoundingProvider(None)
    assert p.covers(tile_at(-80.157, 25.763), FAMILY)
    assert not p.covers(tile_at(5.93, 43.09), FAMILY)
    assert not p.covers(tile_at(-80.157, 25.763), MarineFamily.CONTOURS)

    async def run():
        svc = MarineTileService([p])
        r = await svc.get_tile(tile_at(-80.157, 25.763, 13), FAMILY)
        assert r.status == "below-minzoom" and calls == []
        await svc.get_tile(tile_at(-80.157, 25.763, 14), FAMILY)
        assert len(calls) == 1

    asyncio.run(run())


def test_noaa_mvt_preserves_original_depth_and_unknown_datum():
    point = Sounding(
        id="noaa:harbour:76:1",
        geometry=Point(-80.157, 25.763),
        source="noaa",
        source_id="harbour:76:1",
        source_priority=105,
        value_m=1.25,
        value_original=1.25,
        unit_original="m",
        scale="harbour",
    )

    class Noaa:
        id = "noaa-soundings"
        min_zoom = 14

        def covers(self, tile, family):
            return True

        async def fetch(self, tile, family):
            return ProviderBatch((point,))

    async def run():
        result = await MarineTileService([Noaa()]).get_tile(
            tile_at(-80.157, 25.763, 16), FAMILY
        )
        props = mapbox_vector_tile.decode(result.content)["sounding"]["features"][0][
            "properties"
        ]
        assert props["depth_label"] == "1.25" and props["value_m"] == 1.25
        assert props["nature"] == "point_sounding" and props["source"] == "noaa"
        assert props["unit_original"] == "m"
        assert "vertical_datum" not in props and "sounding_datum" not in props

    asyncio.run(run())


def test_emodnet_failure_never_switches_to_noaa_even_if_coverage_overlaps():
    class Emodnet:
        id = "emodnet-dtm-2024"

        def covers(self, *args):
            return True

        async def fetch(self, *args):
            raise ProviderUnavailable("offline")

    class Noaa:
        id = "noaa-soundings"

        def covers(self, *args):
            return True

        async def fetch(self, *args):
            raise AssertionError("silent fallback")

    async def run():
        service = MarineTileService([Emodnet(), Noaa()])
        with pytest.raises(ProviderUnavailable):
            await service.get_tile(tile_at(5.93, 43.09), FAMILY)
        assert not service._cache

    asyncio.run(run())
