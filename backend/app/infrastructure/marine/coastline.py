"""OSM ocean geometry clips visual PNGs; it never supplies a depth value."""

import asyncio
import time
from collections import OrderedDict
from io import BytesIO

import mapbox_vector_tile
from PIL import Image, ImageChops, ImageDraw
from shapely import contains_xy, union_all
from shapely.geometry import shape

from app.domain.marine import ProviderUnavailable
from app.domain.marine_tile import Tile
from app.infrastructure.marine.visual_water import PADDING, context_neighbours

SIZE = 256
SUBPIXELS = 4


def has_raster_data(content: bytes) -> bool:
    with Image.open(BytesIO(content)) as source:
        if source.size not in {(SIZE, SIZE), (SIZE + 2 * PADDING, SIZE + 2 * PADDING)}:
            raise ProviderUnavailable("Unexpected coastal raster dimensions")
        return source.convert("RGBA").getchannel("A").getbbox() is not None


def rasterize_ocean(content: bytes) -> bytes:
    """Rasterize the tile's published water surfaces, including island holes.

    Coverage antialiasing is restricted to water pixel centres. No dilation,
    arbitrary coastal offset or depth threshold is used. Adjacent tiles share
    the same global pixel lattice; their buffered geometry is not eroded.
    """
    if not content:
        raise ProviderUnavailable("Missing coastline tile")
    layers = mapbox_vector_tile.decode(content)
    geometries = []
    structures = []
    for name in ("ocean", "water_polygons", "pier_polygons"):
        layer = layers.get(name, {})
        extent = layer.get("extent", 4096)
        if not isinstance(extent, (int, float)) or extent <= 0:
            raise ProviderUnavailable("Invalid coastline extent")
        for feature in layer.get("features", []):
            if name == "water_polygons" and feature["properties"].get("kind") not in {
                "dock",
                "canal",
            }:
                continue
            geometry = shape(feature["geometry"])
            if (
                geometry.geom_type not in {"Polygon", "MultiPolygon"}
                or not geometry.is_valid
            ):
                raise ProviderUnavailable("Invalid coastline polygon")
            from shapely.affinity import scale

            target = structures if name == "pier_polygons" else geometries
            target.append(
                scale(geometry, xfact=SIZE / extent, yfact=SIZE / extent, origin=(0, 0))
            )
    water = union_all(geometries).difference(union_all(structures))
    mask = Image.new("L", (SIZE * SUBPIXELS, SIZE * SUBPIXELS), 0)
    draw = ImageDraw.Draw(mask)
    polygons = [] if water.is_empty else [water] if water.geom_type == "Polygon" else getattr(water, "geoms", [])
    for polygon in polygons:
        for index, ring in enumerate([polygon.exterior, *polygon.interiors]):
            draw.polygon(
                [
                    (x * SUBPIXELS - 0.5, (SIZE - y) * SUBPIXELS - 0.5)
                    for x, y in ring.coords
                ],
                fill=255 if index == 0 else 0,
            )
    mask = mask.resize((SIZE, SIZE), Image.Resampling.BOX)
    # A partly covered pixel centred on land must not paint land blue.
    xs = [[x + 0.5 for x in range(SIZE)] for _ in range(SIZE)]
    ys = [[SIZE - y - 0.5] * SIZE for y in range(SIZE)]
    centres = contains_xy(water, xs, ys)
    inside = Image.frombytes(
        "L", (SIZE, SIZE), bytes(255 if v else 0 for v in centres.flat)
    )
    mask = ImageChops.multiply(mask, inside)
    output = BytesIO()
    mask.save(output, format="PNG")
    return output.getvalue()


def apply_ocean_mask(content: bytes, mask: bytes) -> bytes:
    with Image.open(BytesIO(content)) as source, Image.open(BytesIO(mask)) as coastal:
        rgba = source.convert("RGBA")
        if rgba.size != (SIZE, SIZE) or coastal.size != rgba.size:
            raise ProviderUnavailable("Unexpected coastal raster dimensions")
        rgba.putalpha(ImageChops.multiply(rgba.getchannel("A"), coastal.convert("L")))
        output = BytesIO()
        rgba.save(output, format="PNG")
        return output.getvalue()


class CoastlineMask:
    """Bounded RAM mask cache, on the existing persistent OSM HTTP cache."""

    def __init__(self, http, url=None):
        self.http = http
        self.url = (
            url or "https://vector.openstreetmap.org/shortbread_v1/{z}/{x}/{y}.mvt"
        )
        self._cache = OrderedDict()
        self._bytes = 0
        self._flights = [asyncio.Lock() for _ in range(64)]

    async def get_context(self, tile, content):
        """Use published neighbouring water, never extend a clipped polygon."""
        main = await self.get_mask(tile)
        neighbours = await asyncio.to_thread(context_neighbours, content, main)
        context = Image.new("L", (SIZE + 2 * PADDING, SIZE + 2 * PADDING), 0)
        with Image.open(BytesIO(main)) as image:
            context.paste(image, (PADDING, PADDING))

        async def neighbour(dx, dy):
            y = tile.y + dy
            if not 0 <= y < (1 << tile.z):
                return
            target = Tile(tile.z, (tile.x + dx) % (1 << tile.z), y)
            mask = await self.get_mask(target)
            with Image.open(BytesIO(mask)) as image:
                context.paste(image, (PADDING + dx * SIZE, PADDING + dy * SIZE))

        await asyncio.gather(*(neighbour(dx, dy) for dx, dy in neighbours))
        return context

    async def get_mask(self, tile):
        async with self._flights[hash(tile) % len(self._flights)]:
            cached = self._cache.get(tile)
            if cached and cached[0] > time.monotonic():
                self._cache.move_to_end(tile)
                return cached[1]
            content = await self.http.get(
                self.url.format(z=tile.z, x=tile.x, y=tile.y),
                ttl=604800,
                osm=True,
                vector_tile=True,
            )
            try:
                mask = await asyncio.to_thread(rasterize_ocean, content)
            except (ValueError, KeyError, TypeError) as error:
                raise ProviderUnavailable("Invalid coastline tile") from error
            # Another tile can evict this expired entry while HTTP/CPU work
            # yields. Account for the entry that still exists, if any.
            previous = self._cache.pop(tile, None)
            if previous:
                self._bytes -= len(previous[1])
            self._cache[tile] = (time.monotonic() + 604800, mask)
            self._bytes += len(mask)
            while len(self._cache) > 512 or self._bytes > 8 * 1024 * 1024:
                _, old = self._cache.popitem(last=False)
                self._bytes -= len(old[1])
            return mask
