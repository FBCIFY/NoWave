import asyncio
import logging
import time
from collections import OrderedDict
from collections.abc import Iterable
from dataclasses import dataclass

from app.domain.marine import MarineFamily, ProviderBatch, ProviderUnavailable
from app.application.services.marine_merge import merge_features
from app.application.ports.marine_provider import MarineProvider
from app.domain.marine_tile import Tile

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class MarineTileResult:
    content: bytes
    failures: tuple[str, ...] = ()
    sources: tuple[str, ...] = ()


class MarineTileService:
    def __init__(self, providers: Iterable[MarineProvider], encoder=None):
        if encoder is None:
            from app.infrastructure.marine.encoding import encode_tile

            encoder = encode_tile
        self.encoder = encoder
        self.providers = tuple(providers)
        self._cache = OrderedDict()
        self._bytes = 0
        self._flights = [asyncio.Lock() for _ in range(64)]

    def select(self, tile, family):
        return tuple(p for p in self.providers if p.covers(tile, family))

    async def get_tile(self, tile: Tile, family: MarineFamily):
        key = (tile, family)
        async with self._flights[hash(key) % len(self._flights)]:
            cached = self._cache.get(key)
            if cached and cached[0] > time.monotonic():
                self._cache.move_to_end(key)
                return cached[1]
            if tile.z < 10:
                return MarineTileResult(self.encoder(tile, family, []))
            providers = self.select(tile, family)

            async def fetch(provider):
                try:
                    async with asyncio.timeout(14):
                        return await provider.fetch(tile, family)
                except (
                    ProviderUnavailable,
                    ValueError,
                    KeyError,
                    TypeError,
                    TimeoutError,
                ) as exc:
                    logger.warning(
                        "Marine provider %s unavailable: %s",
                        provider.id,
                        type(exc).__name__,
                    )
                    return ProviderBatch(failures=(provider.id + ":unavailable",))

            batches = await asyncio.gather(*(fetch(p) for p in providers))
            failures = tuple(
                sorted(
                    f"{p.id}:{f}"
                    for p, b in zip(providers, batches)
                    for f in b.failures
                )
            )
            successful = [p.id for p, b in zip(providers, batches) if not b.failures]
            fallback = "openwaters" if family == MarineFamily.SEAMARKS else "osm"
            if fallback not in successful and not any(b.features for b in batches):
                # Never cache a transport failure as a successful empty ocean.
                raise ProviderUnavailable("No marine source available")
            features = [f for batch in batches for f in batch.features]
            # Limit to this tile's neighbourhood before the spatial index. Full
            # source geometry is retained for conservative shape comparisons.
            from shapely.geometry import box

            region = box(*tile.query_bounds)
            features = [f for f in features if f.geometry.intersects(region)]
            merged = merge_features(features, tile.bounds)
            result = MarineTileResult(
                self.encoder(tile, family, merged.features),
                failures,
                tuple(sorted({f.source for f in merged.features})),
            )
            if cached:
                self._bytes -= len(cached[1].content)
                self._cache.pop(key)
            self._cache[key] = (time.monotonic() + (15 if failures else 300), result)
            self._bytes += len(result.content)
            while len(self._cache) > 512 or self._bytes > 32 * 1024 * 1024:
                _, old = self._cache.popitem(last=False)
                self._bytes -= len(old[1].content)
            return result
