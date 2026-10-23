"""Reuse finished visual tiles, and share cold requests before occupying workers."""

import asyncio
import logging
import os
import sqlite3
import time
from collections import OrderedDict
from pathlib import Path
from threading import Lock

from app.domain.marine import ProviderUnavailable

logger = logging.getLogger("uvicorn.error.bathymetry")


class UncachedBathymetryTile(bytes):
    """Valid PNG with incomplete optional context; retry on the next request."""


class BathymetryTileCache:
    VERSION = "marine-visual-7"
    TTL = 86400
    MAX_MEMORY = 32 * 1024 * 1024
    MAX_DISK = 128 * 1024 * 1024
    MAX_PENDING = 128
    RESPONSE_TIMEOUT = 24
    QUEUE_TIMEOUT = 8

    def __init__(self, render, path=None, *, concurrency=8):
        self.render = render
        directory = Path(os.getenv(
            "MARINE_CACHE_DIR", str(Path.home() / ".cache/nowave/marine")
        ))
        self.path = Path(path) if path is not None else directory / "bathymetry.sqlite3"
        self._memory = OrderedDict()
        self._bytes = 0
        self._pending = {}
        self._waiters = {}
        self._rendering = set()
        self._slots = asyncio.Semaphore(concurrency)
        self._disk_gate = asyncio.Lock()
        self._db_lock = Lock()
        self._connection = None
        self.metrics = {"memory_hits": 0, "disk_hits": 0, "renders": 0, "shared": 0,
                        "disk_errors": 0, "timeouts": 0}

    def _database(self):
        # Called under _db_lock, on a worker thread. Reuse one serialized
        # connection instead of racing WAL/schema setup for every tile.
        if self._connection is not None:
            return self._connection
        self.path.parent.mkdir(parents=True, exist_ok=True)
        connection = sqlite3.connect(self.path, timeout=2, check_same_thread=False)
        try:
            connection.execute("PRAGMA journal_mode=WAL")
            connection.execute(
                "CREATE TABLE IF NOT EXISTS tiles ("
                "key TEXT PRIMARY KEY, expires REAL NOT NULL, content BLOB NOT NULL)"
            )
            connection.execute("CREATE INDEX IF NOT EXISTS tiles_expiry ON tiles(expires)")
        except BaseException:
            connection.close()
            raise
        self._connection = connection
        return connection

    def _read(self, key):
        try:
            with self._db_lock:
                db = self._database()
                row = db.execute(
                    "SELECT expires, content FROM tiles WHERE key=?", (key,)
                ).fetchone()
                if row and row[0] > time.time():
                    return row
        except (OSError, sqlite3.Error) as error:
            # This cache is optional; unlike the mandatory OSM provider cache,
            # a disk problem may fall back to rendering the same valid PNG.
            self._disk_error("read", error)
        return None

    def _write(self, key, expires, content):
        if len(content) > self.MAX_DISK:
            return
        try:
            with self._db_lock:
                db = self._database()
                with db:
                    db.execute("DELETE FROM tiles WHERE expires <= ?", (time.time(),))
                    db.execute(
                        "INSERT OR REPLACE INTO tiles VALUES (?,?,?)", (key, expires, content)
                    )
                    while db.execute(
                        "SELECT COALESCE(SUM(length(content)),0) FROM tiles"
                    ).fetchone()[0] > self.MAX_DISK:
                        db.execute(
                            "DELETE FROM tiles WHERE key IN ("
                            "SELECT key FROM tiles ORDER BY expires LIMIT 16)"
                        )
        except (OSError, sqlite3.Error) as error:
            self._disk_error("write", error)

    def _disk_error(self, operation, error):
        self.metrics["disk_errors"] += 1
        logger.warning("Bathymetry disk cache %s failed: %s sqlite=%s", operation,
                       error, getattr(error, "sqlite_errorname", "none"))

    async def _disk(self, operation, *args):
        # Queue asynchronously; do not fill the shared executor with threads
        # waiting for SQLite while coastline work also needs that executor.
        async with self._disk_gate:
            return await asyncio.to_thread(operation, *args)

    def _remember(self, key, expires, content):
        previous = self._memory.pop(key, None)
        if previous:
            self._bytes -= len(previous[1])
        if len(content) <= self.MAX_MEMORY:
            self._memory[key] = (expires, content)
            self._bytes += len(content)
        while len(self._memory) > 512 or self._bytes > self.MAX_MEMORY:
            _, old = self._memory.popitem(last=False)
            self._bytes -= len(old[1])

    async def get(self, tile):
        key = f"{self.VERSION}:{tile.z}/{tile.x}/{tile.y}"
        cached = self._memory.get(key)
        if cached and cached[0] > time.time():
            self._memory.move_to_end(key)
            self.metrics["memory_hits"] += 1
            return cached[1]
        task = self._pending.get(key)
        if task is None:
            if len(self._pending) >= self.MAX_PENDING:
                raise ProviderUnavailable("Bathymetry queue is full")
            task = asyncio.create_task(self._load(key, tile))
            self._pending[key] = task
            task.add_done_callback(lambda done: self._finished(key, done))
        else:
            self.metrics["shared"] += 1
        self._waiters[key] = self._waiters.get(key, 0) + 1
        # Share useful work, but discard queued tiles once every caller leaves.
        # Running synchronous renders keep their slot until they actually end.
        try:
            return await asyncio.wait_for(asyncio.shield(task), self.RESPONSE_TIMEOUT)
        except TimeoutError as error:
            # Keep the render's slot until its synchronous work actually ends.
            # Later callers can share it; timeout must not spawn more workers.
            self.metrics["timeouts"] += 1
            raise ProviderUnavailable("Bathymetry response deadline exceeded") from error
        finally:
            remaining = self._waiters[key] - 1
            if remaining:
                self._waiters[key] = remaining
            else:
                self._waiters.pop(key)
                if not task.done() and key not in self._rendering:
                    task.cancel()

    def _finished(self, key, task):
        if self._pending.get(key) is task:
            self._pending.pop(key, None)
        # Observe failures even if every HTTP caller has already disconnected.
        if not task.cancelled():
            task.exception()

    async def _load(self, key, tile):
        started = time.monotonic()
        cached = await self._disk(self._read, key)
        read_done = time.monotonic()
        if cached:
            self.metrics["disk_hits"] += 1
            self._remember(key, *cached)
            return cached[1]
        # Wait asynchronously, before the synchronous EMODnet client enters
        # Starlette's shared worker pool. Other API routes retain their workers.
        try:
            await asyncio.wait_for(self._slots.acquire(), self.QUEUE_TIMEOUT)
        except TimeoutError as error:
            self.metrics["timeouts"] += 1
            raise ProviderUnavailable("Bathymetry render queue deadline exceeded") from error
        render_started = time.monotonic()
        self._rendering.add(key)
        try:
            self.metrics["renders"] += 1
            content = await self.render(tile)
        finally:
            self._rendering.discard(key)
            self._slots.release()
            logger.info("Bathymetry tile=%s disk_ms=%.1f queue_ms=%.1f render_ms=%.1f",
                        key, (read_done - started) * 1000,
                        (render_started - read_done) * 1000,
                        (time.monotonic() - render_started) * 1000)
        if isinstance(content, UncachedBathymetryTile):
            # Keep single-flight and worker limits, but do not persist a
            # degraded render in either positive cache for the normal 24h TTL.
            return content
        expires = time.time() + self.TTL
        self._remember(key, expires, content)
        await self._disk(self._write, key, expires, content)
        return content

    async def close(self):
        tasks = list(self._pending.values())
        for task in tasks:
            task.cancel()
        await asyncio.gather(*tasks, return_exceptions=True)
        self._pending.clear()
        await self._disk(self._close_database)

    def _close_database(self):
        with self._db_lock:
            if self._connection is not None:
                self._connection.close()
                self._connection = None
