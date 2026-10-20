"""Qualified port places from existing Open Waters tiles, available from Z6.

Only the provider's point representation is accepted. Polygon/point pairs share
an OSM identity; no centroid of a clipped polygon, quay or pier is manufactured.
At Z6/Z7, fetch respectively 16/4 Z8 children, on demand and through MarineHTTP's
bounded persistent cache. Z8+ keeps native precision, including overzoom at Z14.
"""

import asyncio
from dataclasses import replace

import mapbox_vector_tile
from shapely.geometry import Point

from app.domain.marine import (
    HarbourFeature, MarineFamily, MergeResult, ProviderBatch, ProviderUnavailable,
)
from app.domain.marine_tile import Tile, unproject


def merge_harbours(features):
    """Merge shared identities only; proximity/name alone cannot prove identity."""
    kept = {}
    matches = []
    for feature in sorted(features, key=lambda f: (-f.source_priority, f.id, f.source_tile)):
        identity = feature.external_ids[0] if feature.external_ids else feature.id
        if identity not in kept:
            kept[identity] = feature
        else:
            previous = kept[identity]
            kept[identity] = replace(
                previous,
                provenance=tuple(sorted(set(previous.provenance + feature.provenance))),
            )
            matches.append((previous.id, feature.id))
    return MergeResult(list(kept.values()), matches)


class HarbourProvider:
    id = "openwaters-harbours"
    url = "https://tiles.openwaters.io/seamap/{z}/{x}/{y}.pbf"

    def __init__(self, http):
        self.http = http

    def covers(self, tile, family):
        return family == MarineFamily.HARBOURS and tile.z >= 6

    async def _tile(self, tile):
        content = await self.http.get(
            self.url.format(z=tile.z, x=tile.x, y=tile.y),
            ttl=86400, vector_tile=True,
        )
        layer = mapbox_vector_tile.decode(content).get("seamark", {}) if content else {}
        extent = layer.get("extent", 4096)
        if not isinstance(extent, (float, int)) or extent <= 0:
            raise ProviderUnavailable("Invalid harbour tile extent")
        w, s, e, n = tile.mercator_bounds
        result = []
        for raw in layer.get("features", []):
            p = raw["properties"]
            if p.get("type") != "harbour" or raw["geometry"]["type"] != "Point":
                continue
            sid = str(p.get("osm_id") or "")
            tile_id = raw.get("id")
            if not sid or not tile_id:
                continue
            x, y = raw["geometry"]["coordinates"]
            lon, lat = unproject(w + x * (e - w) / extent, s + y * (n - s) / extent)
            if not -180 <= lon <= 180:
                continue
            category = str(p.get("seamark:harbour:category") or p.get("category") or "")
            result.append(HarbourFeature(
                id=f"{self.id}:{tile_id}", source=self.id, source_id=sid,
                source_priority=10, geometry=Point(lon, lat),
                name=str(p.get("name") or ""),
                category="marina" if category == "marina" else "harbour",
                source_category=category,
                # Upstream does not publish the OSM element kind; don't invent
                # an osm.org/node URL or match unrelated provider numeric IDs.
                external_ids=(f"openwaters:harbour:{tile_id}",),
                provenance=(f"{self.id}:{tile_id}:osm_id={sid}",),
                source_tile=f"{tile.z}/{tile.x}/{tile.y}",
            ))
        return result

    async def fetch(self, tile, family):
        if not self.covers(tile, family):
            return ProviderBatch()
        factor = 1 << max(0, 8 - tile.z)
        children = [
            Tile(max(8, tile.z), tile.x * factor + x, tile.y * factor + y)
            for x in range(factor) for y in range(factor)
        ]
        # Do not publish partial child coverage as a successful empty region.
        batches = await asyncio.gather(*(self._tile(t) for t in children), return_exceptions=True)
        failures = [b for b in batches if isinstance(b, Exception)]
        if failures:
            raise ProviderUnavailable("Incomplete harbour coverage") from failures[0]
        merged = merge_harbours([f for batch in batches for f in batch])
        return ProviderBatch(tuple(merged.features))
