"""Bounded on-demand upstream access, with a persistent HTTP cache.

OSMF requires caching tiles for at least seven days when expiry is not parsed.
Keep those entries across process restarts; never evict fresh entries to make
room. A full/unwritable cache degrades the provider instead of bypassing it.
"""

import asyncio
import hashlib
import os
import sqlite3
import time
from pathlib import Path
from email.utils import parsedate_to_datetime

import httpx
import mapbox_vector_tile
from google.protobuf.message import DecodeError
from app.domain.marine import ProviderUnavailable


class MarineHTTP:
    MAX_BODY = 8 * 1024 * 1024
    MAX_CACHE = 512 * 1024 * 1024

    def __init__(
        self, cache_path: Path | None = None, transport=None, *, persistent_cache=True
    ):
        self.persistent_cache = persistent_cache
        directory = Path(
            os.getenv("MARINE_CACHE_DIR", str(Path.home() / ".cache/nowave/marine"))
        )
        self.path = cache_path or directory / "http.sqlite3"
        self._client = httpx.AsyncClient(
            transport=transport,
            follow_redirects=True,
            timeout=httpx.Timeout(4, connect=2, pool=2),
            limits=httpx.Limits(max_connections=12, max_keepalive_connections=8),
            headers={"User-Agent": "NoWave/1.0 marine display (https://no-wave.fr)"},
        )
        self._semaphore = asyncio.Semaphore(8 if persistent_cache else 4)
        self._flights = [asyncio.Lock() for _ in range(64)]
        self._database = None
        self._backoff: dict[str, float] = {}
        self._ign_gate = asyncio.Lock()
        self._ign_next_request = 0.0
        self.metrics = {"cache_hits": 0, "network_requests": 0}

    def _db(self):
        if self._database is None:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            self._database = sqlite3.connect(self.path)
            self._database.execute("PRAGMA journal_mode=WAL")
            self._database.execute(
                "CREATE TABLE IF NOT EXISTS responses (key TEXT PRIMARY KEY, expires REAL NOT NULL, body BLOB NOT NULL)"
            )
        return self._database

    async def close(self):
        await self._client.aclose()
        if self._database is not None:
            self._database.close()
            self._database = None

    async def get(
        self, url: str, *, params=None, ttl=21600, osm=False, vector_tile=False
    ) -> bytes:
        if osm:
            if not self.persistent_cache:
                raise ProviderUnavailable("OSM requires its persistent HTTP cache")
            ttl = max(ttl, 604800)
        request = self._client.build_request("GET", url, params=params)
        key = hashlib.sha256(str(request.url).encode()).hexdigest()
        async with self._flights[int(key[:8], 16) % len(self._flights)]:
            try:
                # Numeric NOAA soundings use this existing client without any
                # database or second cache. Other providers retain their policy.
                db = self._db() if self.persistent_cache else None
                now = time.time()
                row = (
                    db.execute(
                        "SELECT expires, body FROM responses WHERE key=?", (key,)
                    ).fetchone()
                    if db is not None
                    else None
                )
                if row and row[0] > now:
                    self.metrics["cache_hits"] += 1
                    return row[1]
                host = request.url.host
                if self._backoff.get(host, 0) > now:
                    raise ProviderUnavailable("Upstream cooling down")
                if db is not None:
                    db.execute("DELETE FROM responses WHERE expires <= ?", (now,))
                    used = db.execute(
                        "SELECT COALESCE(SUM(length(body)),0) FROM responses"
                    ).fetchone()[0]
                    db.commit()
                    if used + self.MAX_BODY > self.MAX_CACHE:
                        raise ProviderUnavailable("Marine HTTP cache is full")
                async with self._semaphore:
                    if host == "data.geopf.fr":
                        # Below the published 30 requests/s/IP. This process
                        # contributes at most 10/s; size worker counts accordingly.
                        async with self._ign_gate:
                            delay = self._ign_next_request - time.monotonic()
                            if delay > 0:
                                await asyncio.sleep(delay)
                            self._ign_next_request = time.monotonic() + 0.1
                    async with self._client.stream(
                        "GET", url, params=params
                    ) as response:
                        self.metrics["network_requests"] += 1
                        if response.status_code in (429, 503):
                            # No retries per tile; avoid multiplying pressure on failure.
                            retry_after = response.headers.get("retry-after", "")
                            try:
                                delay = float(retry_after)
                            except ValueError:
                                try:
                                    delay = (
                                        parsedate_to_datetime(retry_after).timestamp()
                                        - now
                                    )
                                except (ValueError, TypeError, OverflowError):
                                    delay = 30
                            self._backoff[host] = now + max(30, delay)
                        if response.status_code in (204, 404) and (osm or vector_tile):
                            content = b""  # Valid absent tile, also cache it.
                        else:
                            response.raise_for_status()
                            body = bytearray()
                            async for chunk in response.aiter_bytes():
                                body.extend(chunk)
                                if len(body) > self.MAX_BODY:
                                    raise ProviderUnavailable(
                                        "Upstream response exceeds limit"
                                    )
                            content = bytes(body)
                        if osm:
                            # Honour longer max-age as well as the 7-day minimum.
                            for item in response.headers.get("cache-control", "").split(
                                ","
                            ):
                                if item.strip().startswith("max-age="):
                                    try:
                                        ttl = max(
                                            ttl, int(item.strip().split("=", 1)[1])
                                        )
                                    except ValueError:
                                        pass
                # Validate vector-service error payloads before caching them.
                if vector_tile and content:
                    mapbox_vector_tile.decode(content)
                if params and not vector_tile and not osm:
                    import json

                    data = json.loads(content)
                    if (
                        not isinstance(data, dict)
                        or data.get("type") != "FeatureCollection"
                        or not isinstance(data.get("features"), list)
                        or "error" in data
                    ):
                        raise ProviderUnavailable(
                            "Upstream did not return a feature collection"
                        )
                if db is not None:
                    db.execute(
                        "INSERT OR REPLACE INTO responses VALUES (?,?,?)",
                        (key, now + ttl, content),
                    )
                    db.commit()
                return content
            except (
                httpx.HTTPError,
                sqlite3.Error,
                OSError,
                ValueError,
                DecodeError,
            ) as exc:
                if isinstance(exc, httpx.TransportError):
                    self._backoff[request.url.host] = time.time() + 5
                raise ProviderUnavailable(type(exc).__name__) from exc
