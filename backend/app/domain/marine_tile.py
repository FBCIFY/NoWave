import math
from dataclasses import dataclass

from shapely.geometry import box

HALF_WORLD = 20037508.342789244


def project(lon, lat):
    lat = max(-85.05112878, min(85.05112878, lat))
    return lon * HALF_WORLD / 180, math.log(
        math.tan(math.pi / 4 + math.radians(lat) / 2)
    ) * HALF_WORLD / math.pi


def unproject(x, y):
    return x * 180 / HALF_WORLD, math.degrees(
        2 * math.atan(math.exp(y * math.pi / HALF_WORLD)) - math.pi / 2
    )


@dataclass(frozen=True)
class Tile:
    z: int
    x: int
    y: int

    def __post_init__(self):
        if not (
            0 <= self.z <= 16
            and 0 <= self.x < 1 << self.z
            and 0 <= self.y < 1 << self.z
        ):
            raise ValueError("Invalid marine XYZ tile")

    @property
    def mercator_bounds(self):
        span = 2 * HALF_WORLD / (1 << self.z)
        west = -HALF_WORLD + self.x * span
        north = HALF_WORLD - self.y * span
        return west, north - span, west + span, north

    @property
    def bounds(self):
        w, s, e, n = self.mercator_bounds
        return (*unproject(w, s), *unproject(e, n))

    @property
    def polygon(self):
        return box(*self.bounds)

    @property
    def query_bounds(self):
        # Complete neighbours for matching at tile/coverage boundaries.
        w, s, e, n = self.bounds
        latitude_pad = 100 / 111320
        longitude_pad = latitude_pad / max(0.08, math.cos(math.radians((s + n) / 2)))
        return (
            max(-180, w - longitude_pad),
            max(-85.05112878, s - latitude_pad),
            min(180, e + longitude_pad),
            min(85.05112878, n + latitude_pad),
        )

    def parent(self, zoom=12):
        delta = max(0, self.z - zoom)
        return Tile(self.z - delta, self.x >> delta, self.y >> delta)
