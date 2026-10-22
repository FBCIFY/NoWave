"""Reuse finished visual tiles, and share cold requests before occupying workers."""

import asyncio
import logging
import os
import sqlite3
import time
from collections import OrderedDict
from contextlib import closing
from pathlib import Path

from app.domain.marine import ProviderUnavailable

logger = logging.getLogger(__name__)


class BathymetryTileCache:
    VERSION = "marine-palette-3"
    TTL = 86400
    MAX_MEMORY = 32 * 1024 * 1024
    MAX_DISK = 128 * 1024 * 1024
    MAX_PENDING = 128

    def __init__(self, render, path=None, *, concurrency=8):
        self.render = render
        directory = Path(os.getenv(
            "MARINE_CACHE_DIR", str(Path.home() / ".cache/nowave/marine")
        ))
        self.path = Path(path) if path is not None else directory / "bathymetry.sqlite3"
        self._memory = OrderedDict()
        self._bytes = 0
        self._pending = {}
        self._slots = asyncio.Semaphore(concurrency)
        self.metrics = {"memory_hits": 0, "disk_hits": 0, "renders": 0, "shared": 0}

    def _database(self):
        self.path.parent.mkdir(parents=True, exist_ok=True)
        connection = sqlite3.connect(self.path, timeout=0.1)
        try:
            connection.execute("PRAGMA journal_mode=WAL")
            connection.execute(
                "CREATE TABLE IF NOT EXISTS tiles ("
                "key TEXT PRIMARY KEY, expires REAL NOT NULL, content BLOB NOT NULL)"
            )
        except BaseException:
            connection.close()
            raise
        return connection

    def _read(self, key):
        try:
            with closing(self._database()) as db:
                row = db.execute(
                    "SELECT expires, content FROM tiles WHERE key=?", (key,)
                ).fetchone()
                if row and row[0] > time.time():
                    return row
        except (OSError, sqlite3.Error):
            # This cache is optional; unlike the mandatory OSM provider cache,
            # a disk problem may fall back to rendering the same valid PNG.
            logger.warning("Bathymetry disk cache unavailable")
        return None

    def _write(self, key, expires, content):
        if len(content) > self.MAX_DISK:
            return
        try:
            with closing(self._database()) as db, db:
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
        except (OSError, sqlite3.Error):
            logger.warning("Bathymetry disk cache unavailable")

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
        # One cancelled map request must not cancel a tile still used by others.
        return await asyncio.shield(task)

    def _finished(self, key, task):
        self._pending.pop(key, None)
        # Observe failures even if every HTTP caller has already disconnected.
        if not task.cancelled():
            task.exception()

    async def _load(self, key, tile):
        cached = await asyncio.to_thread(self._read, key)
        if cached:
            self.metrics["disk_hits"] += 1
            self._remember(key, *cached)
            return cached[1]
        # Wait asynchronously, before the synchronous EMODnet client enters
        # Starlette's shared worker pool. Other API routes retain their workers.
        async with self._slots:
            self.metrics["renders"] += 1
            content = await self.render(tile)
        expires = time.time() + self.TTL
        self._remember(key, expires, content)
        await asyncio.to_thread(self._write, key, expires, content)
        return content

    async def close(self):
        tasks = list(self._pending.values())
        for task in tasks:
            task.cancel()
        await asyncio.gather(*tasks, return_exceptions=True)
        self._pending.clear()
