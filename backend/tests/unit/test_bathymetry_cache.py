import asyncio
import sqlite3
import time

import pytest

from app.domain.marine_tile import Tile
from app.domain.marine import ProviderUnavailable
from app.infrastructure.adapters.emodnet_bathymetry import BathymetryUnavailable
from app.infrastructure.marine.bathymetry_cache import BathymetryTileCache


TILE = Tile(8, 131, 94)


def test_cold_duplicate_requests_share_one_render_and_survive_a_cancel(tmp_path):
    async def scenario():
        started, release = asyncio.Event(), asyncio.Event()
        calls = 0

        async def render(tile):
            nonlocal calls
            calls += 1
            started.set()
            await release.wait()
            return b"finished coastal png"

        cache = BathymetryTileCache(render, tmp_path / "cache.sqlite3")
        first = asyncio.create_task(cache.get(TILE))
        await started.wait()
        others = [asyncio.create_task(cache.get(TILE)) for _ in range(31)]
        await asyncio.sleep(0)
        first.cancel()
        with pytest.raises(asyncio.CancelledError):
            await first
        release.set()
        assert await asyncio.gather(*others) == [b"finished coastal png"] * 31
        assert await cache.get(TILE) == b"finished coastal png"
        assert calls == 1
        assert cache.metrics["shared"] == 31
        assert cache.metrics["memory_hits"] == 1
        await cache.close()

    asyncio.run(scenario())


def test_distinct_tiles_wait_without_occupying_more_render_workers(tmp_path):
    async def scenario():
        active, peak = 0, 0
        saturated, release = asyncio.Event(), asyncio.Event()

        async def render(tile):
            nonlocal active, peak
            active += 1
            peak = max(peak, active)
            if active == 8:
                saturated.set()
            await release.wait()
            active -= 1
            return b"png"

        cache = BathymetryTileCache(render, tmp_path / "cache.sqlite3")
        tasks = [asyncio.create_task(cache.get(Tile(8, x, 94))) for x in range(32)]
        await asyncio.wait_for(saturated.wait(), 2)
        # The event loop and independent work continue while tiles are queued.
        assert await asyncio.to_thread(lambda: "profile response") == "profile response"
        assert peak == 8
        release.set()
        assert await asyncio.gather(*tasks) == [b"png"] * 32
        assert peak == 8
        await cache.close()

    asyncio.run(scenario())


def test_finished_tile_survives_service_restart_without_provider_or_coastline(tmp_path):
    async def scenario():
        path = tmp_path / "cache.sqlite3"

        async def render(tile):
            return b"fully masked png"

        first = BathymetryTileCache(render, path)
        expected = await first.get(TILE)
        await first.close()

        async def offline(tile):
            raise AssertionError("cache hit must not contact a provider or mask again")

        second = BathymetryTileCache(offline, path)
        assert await second.get(TILE) == expected
        assert second.metrics["disk_hits"] == 1
        assert second.metrics["renders"] == 0
        await second.close()

    asyncio.run(scenario())


def test_failures_are_shared_but_never_cached_as_empty_water(tmp_path):
    async def scenario():
        release = asyncio.Event()
        calls = 0

        async def render(tile):
            nonlocal calls
            calls += 1
            await release.wait()
            if calls == 1:
                raise BathymetryUnavailable("upstream offline")
            return b"recovered png"

        cache = BathymetryTileCache(render, tmp_path / "cache.sqlite3")
        tasks = [asyncio.create_task(cache.get(TILE)) for _ in range(12)]
        await asyncio.sleep(0)
        release.set()
        results = await asyncio.gather(*tasks, return_exceptions=True)
        assert all(isinstance(result, BathymetryUnavailable) for result in results)
        assert calls == 1
        assert await cache.get(TILE) == b"recovered png"
        assert calls == 2
        await cache.close()

    asyncio.run(scenario())


def test_expired_or_other_version_tiles_are_not_reused(tmp_path):
    async def scenario():
        path = tmp_path / "cache.sqlite3"
        calls = 0

        async def render(tile):
            nonlocal calls
            calls += 1
            return b"new png"

        first = BathymetryTileCache(render, path)
        await first.get(TILE)
        await first.close()
        with sqlite3.connect(path) as db:
            db.execute("UPDATE tiles SET expires=?", (time.time() - 1,))
        second = BathymetryTileCache(render, path)
        await second.get(TILE)
        assert calls == 2
        await second.close()
        third = BathymetryTileCache(render, path)
        third.VERSION = "future-coastal-render"
        await third.get(TILE)
        assert calls == 3
        await third.close()

    asyncio.run(scenario())


def test_palette_version_bypasses_old_disk_tile_without_purging_it(tmp_path):
    async def scenario():
        path = tmp_path / "cache.sqlite3"
        with sqlite3.connect(path) as db:
            db.execute(
                "CREATE TABLE tiles (key TEXT PRIMARY KEY, expires REAL NOT NULL, content BLOB NOT NULL)"
            )
            db.execute(
                "INSERT INTO tiles VALUES (?, ?, ?)",
                (f"coast-feather-2:{TILE.z}/{TILE.x}/{TILE.y}", time.time() + 3600, b"old light png"),
            )
        calls = 0

        async def render(tile):
            nonlocal calls
            calls += 1
            return b"new dark png"

        cache = BathymetryTileCache(render, path)
        assert cache.VERSION == "marine-palette-3"
        assert await cache.get(TILE) == b"new dark png"
        assert await cache.get(TILE) == b"new dark png"
        assert calls == 1
        assert cache.metrics["memory_hits"] == 1
        assert cache.MAX_MEMORY == 32 * 1024 * 1024
        with sqlite3.connect(path) as db:
            rows = dict(db.execute("SELECT key, content FROM tiles"))
        assert rows[f"coast-feather-2:{TILE.z}/{TILE.x}/{TILE.y}"] == b"old light png"
        assert rows[f"marine-palette-3:{TILE.z}/{TILE.x}/{TILE.y}"] == b"new dark png"
        await cache.close()

    asyncio.run(scenario())


def test_cache_disk_and_memory_stay_bounded(tmp_path):
    async def scenario():
        async def render(tile):
            return bytes([tile.x]) * 20

        path = tmp_path / "cache.sqlite3"
        cache = BathymetryTileCache(render, path)
        cache.MAX_MEMORY = 50
        cache.MAX_DISK = 100
        for x in range(10):
            await cache.get(Tile(8, x, 94))
        assert cache._bytes <= 50
        with sqlite3.connect(path) as db:
            assert db.execute("SELECT SUM(length(content)) FROM tiles").fetchone()[0] <= 100
        await cache.close()

    asyncio.run(scenario())


def test_unwritable_optional_cache_keeps_a_valid_render(tmp_path):
    async def scenario():
        forbidden = tmp_path / "not-a-directory"
        forbidden.write_text("preserved")

        async def render(tile):
            return b"valid masked png"

        cache = BathymetryTileCache(render, forbidden / "cache.sqlite3")
        assert await cache.get(TILE) == b"valid masked png"
        assert await cache.get(TILE) == b"valid masked png"
        assert forbidden.read_text() == "preserved"
        await cache.close()

    asyncio.run(scenario())


def test_queue_is_bounded_and_shutdown_cancels_waiters(tmp_path):
    async def scenario():
        started = asyncio.Event()

        async def render(tile):
            started.set()
            await asyncio.Event().wait()

        cache = BathymetryTileCache(render, tmp_path / "cache.sqlite3", concurrency=1)
        cache.MAX_PENDING = 2
        first = asyncio.create_task(cache.get(TILE))
        await started.wait()
        second = asyncio.create_task(cache.get(Tile(8, 132, 94)))
        await asyncio.sleep(0)
        with pytest.raises(ProviderUnavailable, match="queue is full"):
            await cache.get(Tile(8, 133, 94))
        await cache.close()
        results = await asyncio.gather(first, second, return_exceptions=True)
        assert all(isinstance(result, asyncio.CancelledError) for result in results)
        assert not cache._pending

    asyncio.run(scenario())
