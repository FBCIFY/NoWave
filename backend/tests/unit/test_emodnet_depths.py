"""Synthetic, offline contract fixtures; no persistent DTM data are used."""

import asyncio
import builtins
import re
import sqlite3
from dataclasses import replace
from urllib.parse import unquote

import httpx
import mapbox_vector_tile
import pytest
from fastapi import HTTPException
from shapely.geometry import Point

from app.application.services.marine_tiles import MarineTileService
from app.domain.marine import MarineFamily, ProviderUnavailable
from app.domain.marine_tile import HALF_WORLD, Tile, project
from app.infrastructure.marine import emodnet_depths as em
from app.infrastructure.marine.encoding import encode_tile

FAMILY = MarineFamily.SOUNDINGS


def tile_at(lon=5.97, lat=43.09, z=16):
    x, y = project(lon, lat)
    return Tile(
        z,
        int((x + HALF_WORLD) / (2 * HALF_WORLD) * 2**z),
        int((HALF_WORLD - y) / (2 * HALF_WORLD) * 2**z),
    )


def csv_body(selection, values=None):
    lines = [",".join(em.CSV_HEADER), "degrees_north,degrees_east,m,,,"]
    for i in selection.latitudes:
        for j in selection.longitudes:
            fields = (values or {}).get((i, j), ("-12.5", "2", "1", "18386"))
            lines.append(
                ",".join(
                    map(
                        str,
                        (
                            em.LAT_ORIGIN + i * em.LAT_STEP,
                            em.LON_ORIGIN + j * em.LON_STEP,
                            *fields,
                        ),
                    )
                )
            )
    return ("\n".join(lines) + "\n").encode()


def selection_from_request(request):
    query = unquote(request.url.query.decode())
    axes = re.findall(r"\[(\d+):(\d+):(\d+)\]", query)
    assert len(axes) == 8 and axes[:2] * 4 == axes
    assert [v.split("[")[0] for v in query.split(",")] == list(em.VARIABLES)
    a, b = [
        range(int(start), int(stop) + 1, int(step)) for start, step, stop in axes[:2]
    ]
    return em.GridSelection(a, b)


def response(request):
    assert request.headers["cache-control"] == "no-store"
    return httpx.Response(200, content=csv_body(selection_from_request(request)))


def decode(content):
    return mapbox_vector_tile.decode(content)["sounding"]["features"]


def test_xyz_world_and_web_mercator_limits():
    assert Tile(0, 0, 0).bounds == pytest.approx(
        (-180, -85.0511287798, 180, 85.0511287798)
    )
    for z in (12, 16):
        assert Tile(z, 0, 0).bounds[3] == pytest.approx(85.0511287798)
        assert Tile(z, 0, 2**z - 1).bounds[1] == pytest.approx(-85.0511287798)


@pytest.mark.parametrize(
    "args", [(-1, 0, 0), (17, 0, 0), (12, -1, 0), (12, 4096, 0), (12, 0, 4096)]
)
def test_invalid_xyz(args):
    with pytest.raises(ValueError):
        Tile(*args)


@pytest.mark.parametrize("z,stride", [(12, 32), (13, 16), (14, 4), (15, 2), (16, 1)])
def test_selection_native_indices_axes_bounds_and_cap(z, stride):
    tile = tile_at(z=z)
    sel = em.grid_selection(tile)
    assert 0 < sel.count <= em.MAX_CELLS
    assert sel.latitudes.step == sel.longitudes.step == stride
    w, s, e, n = tile.bounds
    for i in sel.latitudes:
        assert i % stride == 0
        assert s < em.LAT_ORIGIN + i * em.LAT_STEP <= n
    for j in sel.longitudes:
        assert j % stride == 0
        assert w <= em.LON_ORIGIN + j * em.LON_STEP < e
    assert sel == em.grid_selection(tile)
    assert sel.query.startswith(f"elevation[{sel.latitudes.start}:{stride}:")


@pytest.mark.parametrize("lon,lat", [(-36, 43), (43, 43), (5, 15.001)])
def test_partial_coverage(lon, lat):
    sel = em.grid_selection(tile_at(lon, lat, 14))
    assert sel and sel.count <= em.MAX_CELLS
    assert all(0 <= i < em.LAT_SIZE for i in sel.latitudes)
    assert all(0 <= j < em.LON_SIZE for j in sel.longitudes)


@pytest.mark.parametrize(
    "lon,lat", [(151, -33), (-50, 43), (50, 43), (5, 10), (5, -85)]
)
def test_outside_coverage(lon, lat):
    assert em.grid_selection(tile_at(lon, lat, 12)) is None


def test_adjacent_tiles_own_distinct_cells_and_parent_selection_is_nested():
    for z in range(12, 17):
        t = tile_at(z=z)
        group = [t, Tile(z, t.x + 1, t.y), Tile(z, t.x, t.y + 1)]
        identities = [
            set(
                (i, j)
                for i in em.grid_selection(g).latitudes
                for j in em.grid_selection(g).longitudes
            )
            for g in group
        ]
        assert not identities[0] & identities[1]
        assert not identities[0] & identities[2]
        if z > 12:
            parent = em.grid_selection(t.parent(z - 1))
            parent_ids = {(i, j) for i in parent.latitudes for j in parent.longitudes}
            w, s, e, n = t.bounds
            within = {
                (i, j)
                for i, j in parent_ids
                if w <= em.LON_ORIGIN + j * em.LON_STEP < e
                and s < em.LAT_ORIGIN + i * em.LAT_STEP <= n
            }
            assert within <= identities[0]


@pytest.mark.parametrize(
    "elevation,expected",
    [
        ("-12.4", 12.4),
        ("2", None),
        ("0", None),
        ("NaN", None),
        ("", None),
        ("Infinity", None),
    ],
)
def test_sign_missing_land_and_quality(elevation, expected):
    sel = em.GridSelection(range(26964, 26965), range(40290, 40291))
    fs = em.parse_cells(
        csv_body(sel, {(26964, 40290): (elevation, "0", "1", "-1")}), sel
    )
    if expected is None:
        assert fs == ()
    else:
        f = fs[0]
        assert f.value_m == expected and f.value_original == -expected
        assert f.value_count == 0 and f.interpolation_flag == 1 and f.cdi_index is None
        assert f.nature == f.derivation == "modeled_grid_cell"
        assert f.source == "EMODnet" and f.year == 2024
        assert f.vertical_datum == f.sounding_datum == "LAT" and f.unit_original == "m"
        assert f.accuracy is None and f.provenance == (em.DOI,)


@pytest.mark.parametrize(
    "fields", [("NaN", "NaN", "NaN"), ("-1", "127", "-1"), ("", "", "")]
)
def test_quality_missing_is_not_an_observation(fields):
    sel = em.GridSelection(range(26964, 26965), range(40290, 40291))
    f = em.parse_cells(csv_body(sel, {(26964, 40290): ("-12", *fields)}), sel)[0]
    assert f.value_count is f.interpolation_flag is f.cdi_index is None
    assert f.nature == "modeled_grid_cell"


@pytest.mark.parametrize(
    "depth,label",
    [
        (0.01, "<1"),
        (0.99, "<1"),
        (1, "1"),
        (1.49, "1"),
        (1.5, "2"),
        (12.5, "13"),
        (1234.5, "1235"),
    ],
)
def test_rounding(depth, label):
    assert em.depth_label(depth) == label


@pytest.mark.parametrize(
    "change",
    [
        "header",
        "units",
        "short",
        "extra",
        "duplicate",
        "coordinate",
        "utf8",
        "text",
        "flag",
        "count",
    ],
)
def test_malformed_is_failure_not_empty(change):
    sel = em.grid_selection(tile_at())
    body = csv_body(sel)
    lines = body.splitlines()
    if change == "header":
        lines[0] = b"latitude,longitude,elevation"
    elif change == "units":
        lines[1] = lines[1].replace(b",m,", b",ft,")
    elif change == "short":
        lines.pop()
    elif change == "extra":
        lines.append(lines[-1])
    elif change == "duplicate":
        lines[3] = lines[2]
    elif change == "coordinate":
        lines[2] = b"0,0,-12,1,0,1"
    elif change == "utf8":
        lines[0] = b"\xff"
    elif change == "text":
        lines[2] = lines[2].replace(b"-12.5", b"wrong")
    elif change == "flag":
        lines[2] = lines[2].replace(b",2,1,", b",2,2,")
    elif change == "count":
        lines[2] = lines[2].replace(b",2,1,", b",-2,1,")
    with pytest.raises(em.EmodnetUnavailable, match="malformed-csv"):
        em.parse_cells(b"\n".join(lines), sel)


def test_mvt_contract_dedup_and_native_overzoom():
    tile = tile_at()
    sel = em.grid_selection(tile)
    features = em.parse_cells(csv_body(sel), sel)
    decoded = decode(encode_tile(tile, FAMILY, [*features, *reversed(features)]))
    assert len(decoded) == len(features) <= em.MAX_CELLS
    assert len({f["id"] for f in decoded}) == len(decoded)
    props = decoded[0]["properties"]
    assert props["depth_label"] == "13" and props["value_m"] == 12.5
    assert props["nature"] == "modeled_grid_cell" and props["unit_original"] == "m"
    assert props["interpolation_flag"] == 1 and props["value_count"] == 2
    assert encode_tile(tile, FAMILY, features) == encode_tile(
        tile, FAMILY, reversed(features)
    )
    # Same maxzoom=16 source tile is scaled by Flutter; it has only native IDs.
    assert len(decoded) == sel.count


def test_encoder_cap_and_excludes_adjacent_buffer_points():
    tile = tile_at(z=14)
    sel = em.grid_selection(tile)
    base = em.parse_cells(csv_body(sel), sel)[0]
    cells = [replace(base, id=f"test:{i}") for i in range(100)]
    assert len(decode(encode_tile(tile, FAMILY, cells))) == em.MAX_CELLS
    w, s, e, n = tile.bounds
    for geom in [
        Point(w - 1e-8, (s + n) / 2),
        Point(e, (s + n) / 2),
        Point((w + e) / 2, s),
    ]:
        assert not decode(encode_tile(tile, FAMILY, [replace(base, geometry=geom)]))


def test_single_source_single_flight_ram_cache_and_no_disk(monkeypatch):
    async def run():
        p = em.EmodnetDepthProvider(httpx.MockTransport(response), interval=0)

        class Legacy:
            id = "shom-surveys"

            def covers(self, *args):
                return True

            async def fetch(self, *args):
                raise AssertionError("legacy depth fallback")

        svc = MarineTileService([p, Legacy()])

        # Imports/fixtures are already loaded; any storage open is forbidden.
        def no_write(*args, **kwargs):
            raise AssertionError("persistent storage")

        monkeypatch.setattr(builtins, "open", no_write)
        monkeypatch.setattr(io_module, "open", no_write)
        monkeypatch.setattr(sqlite3, "connect", no_write)
        try:
            results = await asyncio.gather(
                *(svc.get_tile(tile_at(), FAMILY) for _ in range(8))
            )
            assert p.metrics["requests"] == 1
            assert all(r == results[0] for r in results)
            assert results[0].sources == ("EMODnet",)
            assert len(decode(results[0].content)) > 0
            assert len(svc._cache) == 1
            assert await svc.get_tile(tile_at(z=11), FAMILY)
            assert p.metrics["requests"] == 1
            assert (
                await svc.get_tile(tile_at(151, -33), FAMILY)
            ).status == "outside-coverage"
            assert p.metrics["requests"] == 1
        finally:
            await p.close()

    import io as io_module

    asyncio.run(run())


@pytest.mark.parametrize("status", [204, 400, 404, 429, 500, 503])
def test_http_error_not_empty_or_cached(status):
    async def run():
        p = em.EmodnetDepthProvider(
            httpx.MockTransport(lambda r: httpx.Response(status)), interval=0
        )
        try:
            with pytest.raises(em.EmodnetUnavailable, match=f"http-{status}"):
                await p.fetch(tile_at(), FAMILY)
            svc = MarineTileService([p])
            with pytest.raises(ProviderUnavailable):
                await svc.get_tile(tile_at(), FAMILY)
            assert not svc._cache
        finally:
            await p.close()

    asyncio.run(run())


@pytest.mark.parametrize(
    "kind", ["timeout", "transport", "large-header", "large-body", "malformed"]
)
def test_network_failure_reasons(kind):
    def handler(request):
        if kind == "timeout":
            raise httpx.ReadTimeout("timeout")
        if kind == "transport":
            raise httpx.ConnectError("offline")
        if kind == "large-header":
            return httpx.Response(200, headers={"content-length": str(em.MAX_BODY + 1)})
        if kind == "large-body":
            return httpx.Response(200, content=b"x" * (em.MAX_BODY + 1))
        return httpx.Response(200, content=b'Error { message="broken"; }')

    async def run():
        p = em.EmodnetDepthProvider(httpx.MockTransport(handler), interval=0)
        reason = (
            "body-limit"
            if kind.startswith("large")
            else "malformed-csv"
            if kind == "malformed"
            else kind
        )
        try:
            with pytest.raises(em.EmodnetUnavailable, match=reason):
                await p.fetch(tile_at(), FAMILY)
        finally:
            await p.close()

    asyncio.run(run())


def test_concurrency_rate_cancellation_and_retry():
    async def run():
        active = peak = 0
        starts = []

        async def handler(request):
            nonlocal active, peak
            active += 1
            peak = max(peak, active)
            starts.append(asyncio.get_running_loop().time())
            try:
                await asyncio.sleep(0.04)
                return response(request)
            finally:
                active -= 1

        p = em.EmodnetDepthProvider(httpx.MockTransport(handler), interval=0.015)
        try:
            await asyncio.gather(*(p.fetch(tile_at(), FAMILY) for _ in range(4)))
            assert peak == 2
            assert all(b - a >= 0.014 for a, b in zip(starts, starts[1:]))
            svc = MarineTileService([p])
            task = asyncio.create_task(svc.get_tile(tile_at(), FAMILY))
            await asyncio.sleep(0.02)
            task.cancel()
            with pytest.raises(asyncio.CancelledError):
                await task
            assert not svc._cache
            assert decode((await svc.get_tile(tile_at(), FAMILY)).content)
        finally:
            await p.close()

    asyncio.run(run())


def test_empty_missing_cells_is_success_and_disabled_is_error():
    def empty(request):
        sel = selection_from_request(request)
        values = {
            (i, j): ("NaN", "-1", "127", "-1")
            for i in sel.latitudes
            for j in sel.longitudes
        }
        return httpx.Response(200, content=csv_body(sel, values))

    async def run():
        p = em.EmodnetDepthProvider(httpx.MockTransport(empty), interval=0)
        try:
            svc = MarineTileService([p])
            result = await svc.get_tile(tile_at(), FAMILY)
            assert result.status == "empty" and not decode(result.content)
            assert svc._cache
            with pytest.raises(ProviderUnavailable, match="disabled"):
                await MarineTileService([]).get_tile(tile_at(), FAMILY)
        finally:
            await p.close()

    asyncio.run(run())


def test_route_disconnect_cancels_upstream_and_does_not_cache(monkeypatch):
    from app.api.routes import map_tiles

    async def run():
        started, cancelled = asyncio.Event(), asyncio.Event()

        async def handler(request):
            started.set()
            try:
                await asyncio.Future()
            finally:
                cancelled.set()

        p = em.EmodnetDepthProvider(httpx.MockTransport(handler), interval=0)
        svc = MarineTileService([p])
        monkeypatch.setattr(map_tiles, "get_marine_service", lambda: svc)

        class Request:
            async def is_disconnected(self):
                return started.is_set()

        try:
            t = tile_at()
            with pytest.raises(HTTPException) as exc:
                await map_tiles.get_sounding_tile(Request(), t.z, t.x, t.y)
            assert exc.value.status_code == 499 and cancelled.is_set()
            assert not svc._cache
        finally:
            await p.close()

    asyncio.run(run())


def test_absolute_deadline_includes_queue_and_releases_capacity(monkeypatch):
    monkeypatch.setattr(em, "REQUEST_DEADLINE", 0.03)

    async def run():
        cancelled = 0

        async def handler(request):
            nonlocal cancelled
            try:
                await asyncio.Future()
            finally:
                cancelled += 1

        p = em.EmodnetDepthProvider(httpx.MockTransport(handler), interval=0)
        try:
            results = await asyncio.gather(
                *(p.fetch(tile_at(), FAMILY) for _ in range(3)),
                return_exceptions=True,
            )
            assert all(
                isinstance(r, em.EmodnetUnavailable) and r.reason == "timeout"
                for r in results
            )
            assert cancelled == 2 and p._semaphore._value == 2
        finally:
            await p.close()

    asyncio.run(run())


@pytest.mark.parametrize(
    "kind,code,state",
    [
        ("valid", 200, "ok"),
        ("missing", 200, "empty"),
        ("outside", 200, "outside-coverage"),
        ("low", 200, "below-minzoom"),
        ("error", 503, "unavailable"),
    ],
)
def test_real_route_with_mock_erddap_schema_and_status(monkeypatch, kind, code, state):
    from fastapi.testclient import TestClient
    from app.main import app
    from app.api.routes import map_tiles

    def handler(request):
        if kind == "error":
            return httpx.Response(500)
        sel = selection_from_request(request)
        values = (
            {
                (i, j): ("NaN", "-1", "127", "-1")
                for i in sel.latitudes
                for j in sel.longitudes
            }
            if kind == "missing"
            else None
        )
        return httpx.Response(200, content=csv_body(sel, values))

    p = em.EmodnetDepthProvider(httpx.MockTransport(handler), interval=0)
    service = MarineTileService([p])
    monkeypatch.setattr(map_tiles, "get_marine_service", lambda: service)
    tile = (
        tile_at(151, -33)
        if kind == "outside"
        else tile_at(z=11 if kind == "low" else 16)
    )
    try:
        # Match existing route tests: no application lifespan/database teardown.
        r = TestClient(app).get(f"/api/v1/map/soundings/{tile.z}/{tile.x}/{tile.y}.pbf")
        assert r.status_code == code and r.headers["cache-control"] == "no-store"
        assert r.headers["x-nowave-marine-status"] == state
        if kind == "valid":
            assert decode(r.content)[0]["properties"]["depth_label"] == "13"
            assert r.headers["x-nowave-marine-sources"] == "EMODnet"
        elif code == 200:
            assert decode(r.content) == []
        if kind in {"outside", "low"}:
            assert p.metrics["requests"] == 0
        if kind == "error":
            assert not service._cache
    finally:
        asyncio.run(p.close())


@pytest.mark.parametrize(
    "path", ["-1/0/0", "17/0/0", "12/4096/0", "12/0/4096", "12/-1/0"]
)
def test_route_invalid_xyz_never_accesses_provider(monkeypatch, path):
    from fastapi.testclient import TestClient
    from app.main import app
    from app.api.routes import map_tiles

    def unexpected():
        raise AssertionError("provider called for invalid XYZ")

    monkeypatch.setattr(map_tiles, "get_marine_service", unexpected)
    assert TestClient(app).get(f"/api/v1/map/soundings/{path}.pbf").status_code == 422


def test_runtime_has_unique_mvp_source_and_retains_other_layers():
    from app.infrastructure.marine import runtime

    async def run():
        await runtime.close_marine_service()
        service = runtime.get_marine_service()
        try:
            assert [p.id for p in service.select(tile_at(), FAMILY)] == [em.PROVIDER_ID]
            assert [p.id for p in service.select(tile_at(-80, 25), FAMILY)] == [
                "noaa-soundings"
            ]
            assert runtime._sounding_http.persistent_cache is False
            assert runtime._sounding_http._database is None
            assert "shom-hazards" in {
                p.id for p in service.select(tile_at(), MarineFamily.HAZARDS)
            }
            assert "emodnet-contours" in {
                p.id for p in service.select(tile_at(), MarineFamily.CONTOURS)
            }
            assert runtime._http._database is None
        finally:
            await runtime.close_marine_service()

    asyncio.run(run())


def test_existing_ram_cache_eviction_is_bounded():
    async def run():
        p = em.EmodnetDepthProvider(httpx.MockTransport(response), interval=0)
        try:
            service = MarineTileService([p])
            # All outside Europe: no network traffic, same cache code as wet tiles.
            for x in range(513):
                await service.get_tile(Tile(12, x, 1000), FAMILY)
            assert len(service._cache) == 512 and p.metrics["requests"] == 0
            assert service._bytes == sum(
                len(r.content) for _, r in service._cache.values()
            )
            assert service._bytes <= 32 * 1024 * 1024
        finally:
            await p.close()

    asyncio.run(run())
