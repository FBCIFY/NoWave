"""Small per-process cache; PostgreSQL remains authoritative on every request."""

from collections import OrderedDict
from dataclasses import dataclass
from datetime import datetime
from threading import Lock
from time import monotonic
from uuid import UUID


@dataclass(frozen=True)
class TileEntry:
    revision: UUID
    content: bytes
    deadline: float
    expires_at: datetime | None


class MapTileCache:
    def __init__(self, *, max_bytes=16 * 1024 * 1024, max_entries=512, ttl=15):
        self.max_bytes = max_bytes
        self.max_entries = max_entries
        self.ttl = ttl
        self._entries = OrderedDict()
        self._bytes = 0
        self._lock = Lock()
        # Fixed-size single-flight locks: never accumulate locks for arbitrary URLs.
        self._flights = [Lock() for _ in range(32)]

    def flight(self, key):
        return self._flights[hash(key) % len(self._flights)]

    def get(self, key, revision, database_now):
        with self._lock:
            entry = self._entries.get(key)
            if entry is None:
                return None
            if (
                entry.revision != revision
                or monotonic() >= entry.deadline
                or (entry.expires_at is not None and database_now >= entry.expires_at)
            ):
                self._remove(key)
                return None
            self._entries.move_to_end(key)
            return entry.content

    def put(self, key, revision, content, expires_at, started):
        with self._lock:
            if key in self._entries:
                self._remove(key)
            if len(content) > self.max_bytes or monotonic() >= started + self.ttl:
                return
            self._entries[key] = TileEntry(revision, content, started + self.ttl, expires_at)
            self._bytes += len(content)
            while len(self._entries) > self.max_entries or self._bytes > self.max_bytes:
                self._remove(next(iter(self._entries)))

    def _remove(self, key):
        self._bytes -= len(self._entries.pop(key).content)


tile_cache = MapTileCache()
