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
    status: str = "ok"


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
        candidates = tuple(p for p in self.providers if p.covers(tile, family))
        if family != MarineFamily.SOUNDINGS:
            return candidates
        # Geographic selection, never a transport fallback. Keep the European
        # MVP exclusively EMODnet; restore ENC observations in NOAA coverage.
        emodnet = tuple(p for p in candidates if p.id == "emodnet-dtm-2024")
        return emodnet or tuple(p for p in candidates if p.id == "noaa-soundings")

    async def get_tile(self, tile: Tile, family: MarineFamily, *, geojson=False):
        from app.infrastructure.marine.hydro_encoding import MIN_ZOOM

        started = time.monotonic()
        key = (tile, family, geojson)
        if geojson:
            from app.infrastructure.marine.viewport_encoding import encode_viewport_tile

        encode = encode_viewport_tile if geojson else self.encoder
        async with self._flights[hash(key) % len(self._flights)]:
            cached = self._cache.get(key)
            if cached and cached[0] > time.monotonic():
                self._cache.move_to_end(key)
                return cached[1]
            if tile.z < (6 if family == MarineFamily.HARBOURS else MIN_ZOOM.get(family, 10)):
                return MarineTileResult(
                    encode(tile, family, []),
                    status="below-minzoom"
                    if family == MarineFamily.SOUNDINGS
                    else "ok",
                )
            providers = self.select(tile, family)
            if (
                family == MarineFamily.SOUNDINGS
                and not providers
                and not any(p.id == "emodnet-dtm-2024" for p in self.providers)
            ):
                raise ProviderUnavailable("EMODnet depth provider disabled")
            if (
                family == MarineFamily.SOUNDINGS
                and providers
                and all(tile.z < getattr(p, "min_zoom", 12) for p in providers)
            ):
                return MarineTileResult(
                    encode(tile, family, []), status="below-minzoom"
                )

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
                        getattr(exc, "reason", type(exc).__name__),
                    )
                    return ProviderBatch(
                        failures=(
                            getattr(exc, "reason", "unavailable")
                            if family == MarineFamily.SOUNDINGS
                            else provider.id + ":unavailable",
                        )
                    )

            batches = await asyncio.gather(*(fetch(p) for p in providers))
            failures = tuple(
                sorted(
                    f"{p.id}:{f}"
                    for p, b in zip(providers, batches)
                    for f in b.failures
                )
            )
            successful = [p.id for p, b in zip(providers, batches) if not b.failures]
            fallback = (
                "openwaters-harbours" if family == MarineFamily.HARBOURS
                else "openwaters" if family == MarineFamily.SEAMARKS else "osm"
            )
            hydro = family in MIN_ZOOM
            if (
                hydro
                and providers
                and not successful
                and not any(b.features for b in batches)
            ) or (
                not hydro
                and fallback not in successful
                and not any(b.features for b in batches)
            ):
                # Never cache a transport failure as a successful empty ocean.
                raise ProviderUnavailable("No marine source available")
            features = [f for batch in batches for f in batch.features]
            # Limit to this tile's neighbourhood before the spatial index. Full
            # source geometry is retained for conservative shape comparisons.
            from shapely.geometry import box

            region = box(*tile.query_bounds)
            features = [f for f in features if f.geometry.intersects(region)]
            if family == MarineFamily.HARBOURS:
                from app.infrastructure.marine.harbours import merge_harbours

                merged = merge_harbours(features)
            else:
                merged = merge_features(features, tile.bounds)
            result = MarineTileResult(
                encode(tile, family, merged.features),
                failures,
                tuple(sorted({f.source for f in merged.features})),
                (
                    "outside-coverage"
                    if not providers
                    else "empty"
                    if not merged.features
                    else "ok"
                )
                if family == MarineFamily.SOUNDINGS
                else "ok",
            )
            if hydro:
                logger.info(
                    "Hydro tile %s/%s/%s/%s features=%s bytes=%s ms=%.1f providers=%s failures=%s",
                    family.value,
                    tile.z,
                    tile.x,
                    tile.y,
                    len(merged.features),
                    len(result.content),
                    (time.monotonic() - started) * 1000,
                    len(providers),
                    len(failures),
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
