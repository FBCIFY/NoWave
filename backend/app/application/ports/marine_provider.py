from typing import Protocol

from app.domain.marine import MarineFamily, ProviderBatch
from app.domain.marine_tile import Tile


class MarineProvider(Protocol):
    id: str

    def covers(self, tile: Tile, family: MarineFamily) -> bool: ...

    async def fetch(self, tile: Tile, family: MarineFamily) -> ProviderBatch: ...
