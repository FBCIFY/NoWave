from datetime import UTC, datetime, timedelta
from uuid import uuid4

import app.infrastructure.cache.map_tile_cache as module
from app.infrastructure.cache.map_tile_cache import MapTileCache


def test_cache_rejects_changed_revision_expiration_and_ttl(monkeypatch):
    clock = [100.0]
    monkeypatch.setattr(module, "monotonic", lambda: clock[0])
    now = datetime.now(UTC)
    revision = uuid4()
    cache = MapTileCache()
    cache.put("tile", revision, b"mvt", now + timedelta(seconds=2), clock[0])
    assert cache.get("tile", revision, now) == b"mvt"
    assert cache.get("tile", revision, now + timedelta(seconds=2)) is None
    cache.put("tile", revision, b"mvt", None, clock[0])
    assert cache.get("tile", uuid4(), now) is None
    cache.put("tile", revision, b"", None, clock[0])
    assert cache.get("tile", revision, now) == b""
    clock[0] += 15
    assert cache.get("tile", revision, now) is None


def test_cache_limits_memory_and_entry_count(monkeypatch):
    monkeypatch.setattr(module, "monotonic", lambda: 100)
    now, revision = datetime.now(UTC), uuid4()
    cache = MapTileCache(max_bytes=4, max_entries=2)
    for key in ("first", "second"):
        cache.put(key, revision, b"xx", None, 100)
    assert cache.get("first", revision, now) == b"xx"
    cache.put("third", revision, b"xx", None, 100)
    assert cache.get("second", revision, now) is None
    cache.put("large", revision, b"xxxxx", None, 100)
    assert cache.get("large", revision, now) is None
    cache.put("empty", revision, b"", None, 100)
    assert cache.get("first", revision, now) is None
    assert cache.get("third", revision, now) == b"xx"


def test_long_build_does_not_extend_ttl(monkeypatch):
    monkeypatch.setattr(module, "monotonic", lambda: 116)
    cache = MapTileCache()
    revision = uuid4()
    cache.put("tile", revision, b"old", None, 100)
    assert cache.get("tile", revision, datetime.now(UTC)) is None
