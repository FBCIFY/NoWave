"""Exercise cancellation through the real HTTPX/httpcore pool, without sockets."""

import asyncio
from collections import deque
from contextlib import asynccontextmanager
import hashlib

import anyio
import httpcore
from httpcore._backends.mock import AsyncMockBackend, AsyncMockStream
import httpx
import pytest

from app.domain.marine import MarineFamily
from app.domain.marine_tile import HALF_WORLD, Tile, project
from app.infrastructure.marine import emodnet_depths as em
from app.infrastructure.marine.cancellation import cancellation_safe
from app.infrastructure.marine.http import MarineHTTP


class ReadGate:
    def __init__(self, content):
        self.content = content
        self.entered = asyncio.Event()
        self.release = asyncio.Event()

    async def read(self):
        self.entered.set()
        await self.release.wait()
        return self.content


class ScriptedStream(AsyncMockStream):
    def __init__(self, backend):
        super().__init__([])
        self.backend = backend

    async def write(self, buffer, timeout=None):
        if buffer.startswith(b"GET "):
            self.backend.requests += 1
            self._buffer.extend(self.backend.responses.popleft())

    async def read(self, max_bytes, timeout=None):
        if self._buffer and isinstance(self._buffer[0], ReadGate):
            return await self._buffer.pop(0).read()
        return await super().read(max_bytes, timeout)


class ScriptedNetwork(AsyncMockBackend):
    """Only the byte-level network is simulated; HTTP parsing/pooling is real."""

    def __init__(self, responses):
        super().__init__([])
        self.responses = deque(responses)
        self.requests = 0

    async def connect_tcp(self, *args, **kwargs):
        return ScriptedStream(self)


class CloseGate:
    def __init__(self):
        self.entered = asyncio.Event()
        self.release = asyncio.Event()

    async def trace(self, name, info):
        if name == "http11.response_closed.started" and not self.entered.is_set():
            self.entered.set()
            await self.release.wait()


def raw_response(status=200, body=b"recovered", headers=()):
    return (
        f"HTTP/1.1 {status} Test\r\nContent-Length: {len(body)}\r\n".encode()
        + b"".join(f"{key}: {value}\r\n".encode() for key, value in headers)
        + b"\r\n" + body
    )


def transport_for(responses, *, max_connections=1, max_keepalive_connections=1):
    network = ScriptedNetwork(responses)
    transport = httpx.AsyncHTTPTransport()
    # The native pool is deliberately one slot: one orphan makes recovery fail.
    transport._pool = httpcore.AsyncConnectionPool(
        max_connections=max_connections,
        max_keepalive_connections=max_keepalive_connections,
        network_backend=network,
    )
    return transport, network


def install_close_gate(client, gate):
    async def hook(request):
        request.extensions["trace"] = gate.trace

    client.event_hooks = {"request": [hook], "response": []}
    client.timeout = httpx.Timeout(0.2, pool=0.2)


def assert_pool_released(transport):
    assert transport._pool._requests == []
    assert all(connection.is_idle() or connection.is_closed()
               for connection in transport._pool.connections)


async def wait_until(predicate):
    async with asyncio.timeout(2):
        while not predicate():
            await asyncio.sleep(0)


async def cancel_at_gate(task, gate, *, repeated=False):
    await asyncio.wait_for(gate.entered.wait(), 2)
    task.cancel()
    await asyncio.sleep(0)
    if repeated:
        task.cancel()
        await asyncio.sleep(0)
    gate.release.set()
    with pytest.raises(asyncio.CancelledError):
        await asyncio.wait_for(task, 2)


def assert_no_cache(client):
    if not isinstance(client, MarineHTTP):
        assert client._cooldown == 0
    elif client.persistent_cache:
        assert client._db().execute("SELECT count(*) FROM responses").fetchone() == (0,)
    else:
        assert client._database is None


def sounding_tile():
    x, y = project(5.97, 43.09)
    return Tile(16, int((x + HALF_WORLD) / (2 * HALF_WORLD) * 2**16),
                int((HALF_WORLD - y) / (2 * HALF_WORLD) * 2**16))


def sounding_csv():
    selection = em.grid_selection(sounding_tile())
    rows = [",".join(em.CSV_HEADER), "degrees_north,degrees_east,m,,,"]
    for i in selection.latitudes:
        for j in selection.longitudes:
            rows.append(",".join(map(str, (
                em.LAT_ORIGIN + i * em.LAT_STEP,
                em.LON_ORIGIN + j * em.LON_STEP, -12.5, 2, 1, 18386,
            ))))
    return ("\n".join(rows) + "\n").encode()


def capacity(kind):
    return {"persistent": 12, "noaa": 4, "emodnet": 2}[kind]


@asynccontextmanager
async def provider_case(kind, tmp_path, responses, gate=None):
    transport, network = transport_for(responses)
    client = (em.EmodnetDepthProvider(transport, interval=0) if kind == "emodnet"
              else MarineHTTP(tmp_path / "cache.sqlite3", transport,
                              persistent_cache=kind == "persistent"))
    if isinstance(gate, CloseGate):
        install_close_gate(client._client, gate)
    try:
        yield client, transport, network
    finally:
        if gate:
            gate.release.set()
        await client.close()


async def fetch(client, url="http://provider.test/interrupted", **kwargs):
    if isinstance(client, em.EmodnetDepthProvider):
        return await client.fetch(sounding_tile(), MarineFamily.SOUNDINGS)
    return await client.get(url, **kwargs)


async def assert_recovered(client, transport, network, kind, *, requests=2, body=b"recovered"):
    result = await fetch(client, "http://provider.test/recovery")
    assert result.features if kind == "emodnet" else result == body
    assert network.requests == requests
    assert client._semaphore._value == capacity(kind)
    assert_pool_released(transport)


@pytest.mark.parametrize("kind,scenario,repeated", [
    (kind, status, repeated)
    for kind in ("persistent", "noaa", "emodnet")
    for status in (404, 200)
    for repeated in (False, True)
] + [(kind, "body", False) for kind in ("persistent", "noaa", "emodnet")]
  + [("persistent", scenario, False) for scenario in ("redirect", "error", "body-limit")])
def test_cancelled_stream_releases_pool_without_caching_and_recovers(
    tmp_path, kind, scenario, repeated,
):
    async def run():
        body = sounding_csv() if kind == "emodnet" else b"recovered"
        gate = CloseGate()
        if scenario == "body":
            gate = ReadGate(body[3:])
            headers = f"HTTP/1.1 200 OK\r\nContent-Length: {len(body)}\r\n\r\n".encode()
            first = [headers + body[:3], gate]
        elif scenario == "redirect":
            first = [raw_response(302, b"redirect", (("Location", "/redirected"),))]
        elif scenario == "error":
            first = [raw_response(500, b"error")]
        elif scenario == "body-limit":
            first = [raw_response(body=b"too-large")]
            body = b"ok"
        else:
            first = [raw_response(scenario, body)]
        responses = [first, [raw_response(body=body)]]
        async with provider_case(kind, tmp_path, responses, gate) as (client, transport, network):
            if scenario == "body-limit":
                client.MAX_BODY = 4
            task = asyncio.create_task(fetch(client, vector_tile=scenario == 404))
            await cancel_at_gate(task, gate, repeated=repeated)
            assert_no_cache(client)
            assert_pool_released(transport)
            await assert_recovered(client, transport, network, kind, body=body)

    asyncio.run(run())


def test_cancelled_anyio_parent_joins_delayed_real_pool_cleanup(tmp_path):
    async def run():
        gate = CloseGate()
        finished = anyio.Event()
        scopes = []
        cancellations = []

        async def caller():
            with anyio.CancelScope() as scope:
                scopes.append(scope)
                try:
                    await client.get("http://provider.test/interrupted", vector_tile=True)
                except asyncio.CancelledError:
                    cancellations.append(True)
                    raise
            finished.set()

        responses = [[raw_response(404, b"interrupted")], [raw_response()]]
        async with provider_case("persistent", tmp_path, responses, gate) as (client, transport, network):
            with anyio.fail_after(2):
                async with anyio.create_task_group() as group:
                    group.start_soon(caller)
                    await gate.entered.wait()
                    scopes[0].cancel()
                    await anyio.sleep(0.01)
                    assert not finished.is_set()
                    gate.release.set()
                    await finished.wait()
            assert cancellations == [True]
            assert_no_cache(client)
            assert_pool_released(transport)
            await assert_recovered(client, transport, network, "persistent")

    anyio.run(run)


def test_cancellation_before_helper_start_never_calls_operation():
    async def run():
        called = False

        async def operation():
            nonlocal called
            called = True

        async def caller():
            asyncio.current_task().cancel()
            await cancellation_safe(operation)

        with pytest.raises(asyncio.CancelledError):
            await caller()
        assert not called

    asyncio.run(run())


def test_previously_handled_cancellation_does_not_prevent_new_operation():
    async def run():
        async def operation():
            return "recovered"

        asyncio.current_task().cancel()
        try:
            await asyncio.sleep(0)
        except asyncio.CancelledError:
            pass
        assert await cancellation_safe(operation) == "recovered"

    asyncio.run(run())


@pytest.mark.parametrize("kind", ["persistent", "noaa", "emodnet"])
@pytest.mark.parametrize("waiting", [False, True])
def test_cancel_before_network_or_waiting_for_capacity(tmp_path, kind, waiting):
    async def run():
        responses = [[raw_response(body=sounding_csv())]]
        async with provider_case(kind, tmp_path, responses) as (client, transport, network):
            acquired = 0
            try:
                if waiting:
                    while client._semaphore._value:
                        await client._semaphore.acquire()
                        acquired += 1
                task = asyncio.create_task(fetch(client))
                if waiting:
                    await wait_until(lambda: bool(client._semaphore._waiters))
                task.cancel()
                with pytest.raises(asyncio.CancelledError):
                    await asyncio.wait_for(task, 2)
                assert network.requests == 0
                assert_pool_released(transport)
            finally:
                for _ in range(acquired):
                    client._semaphore.release()
            await assert_recovered(client, transport, network, kind,
                                   requests=1, body=sounding_csv())

    asyncio.run(run())


@pytest.mark.parametrize("outer", [True, False])
def test_emodnet_parent_timeout_preserves_cleanup_and_timeout_contract(tmp_path, monkeypatch, outer):
    async def run():
        gate = CloseGate()

        async def operation():
            if outer:
                async with asyncio.timeout(0.03):
                    return await provider.fetch(sounding_tile(), MarineFamily.SOUNDINGS)
            return await provider.fetch(sounding_tile(), MarineFamily.SOUNDINGS)

        if not outer:
            monkeypatch.setattr(em, "REQUEST_DEADLINE", 0.03)
        responses = [[raw_response(body=sounding_csv())] for _ in range(2)]
        async with provider_case("emodnet", tmp_path, responses, gate) as (provider, transport, network):
            task = asyncio.create_task(operation())
            await asyncio.wait_for(gate.entered.wait(), 2)
            await asyncio.sleep(0.06)
            gate.release.set()
            expected = TimeoutError if outer else em.EmodnetUnavailable
            with pytest.raises(expected) as caught:
                await asyncio.wait_for(task, 2)
            if not outer:
                assert caught.value.reason == "timeout"
            assert_pool_released(transport)
            assert provider._semaphore._value == 2
            provider._cooldown = 0
            await assert_recovered(provider, transport, network, "emodnet")

    asyncio.run(run())


def test_marine_capacity_leaves_connection_headroom(tmp_path):
    async def run():
        clients = [(MarineHTTP(tmp_path / "shared.sqlite3"), 12, 24, 12),
                   (MarineHTTP(persistent_cache=False), 4, 12, 8),
                   (em.EmodnetDepthProvider(), 2, 2, 2)]
        try:
            for client, slots, connections, keepalive in clients:
                assert client._semaphore._value == slots
                pool = client._client._transport._pool
                assert pool._max_connections == connections
                assert pool._max_keepalive_connections == keepalive
        finally:
            for client, *_ in clients:
                await client.close()

    asyncio.run(run())


def test_shared_marine_network_admits_twelve_requests_and_queues_thirteenth(tmp_path):
    async def run():
        # Distinct single-flight stripes let this exercise the network semaphore.
        urls = {}
        for i in range(1000):
            url = f"http://provider.test/tile-{i}"
            slot = int(hashlib.sha256(url.encode()).hexdigest()[:8], 16) % 64
            urls.setdefault(slot, url)
            if len(urls) == 13:
                break
        assert len(urls) == 13
        gate = ReadGate(b"shared")
        transport, network = transport_for([
            [b"HTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\n", gate]
            for _ in urls
        ], max_connections=24, max_keepalive_connections=12)
        client = MarineHTTP(tmp_path / "cache.sqlite3", transport)
        tasks = [asyncio.create_task(client.get(url)) for url in urls.values()]
        try:
            await wait_until(lambda: network.requests == 12)
            await wait_until(lambda: bool(client._semaphore._waiters))
            assert network.requests == 12
            assert len(transport._pool._requests) == 12
            assert not any(task.done() for task in tasks)
            gate.release.set()
            assert await asyncio.wait_for(asyncio.gather(*tasks), 2) == [b"shared"] * 13
            assert network.requests == 13
            assert client._semaphore._value == 12
            assert_pool_released(transport)
        finally:
            gate.release.set()
            await asyncio.gather(*tasks, return_exceptions=True)
            await client.close()

    asyncio.run(run())
