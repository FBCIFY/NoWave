"""On-demand EMODnet DTM 2024 cells. No disk cache or regional downloads.

DDS/DAS and CSV verified against the live service on 2026-10-18. Both axes
increase, ordered [latitude][longitude], cell centres at 1/960 degree. See
docs/architecture/emodnet-depths.md for the pinned contract and limitations.
"""

import asyncio
import csv
import io
import logging
import math
import time
from dataclasses import dataclass
from decimal import Decimal, ROUND_HALF_UP
from urllib.parse import quote

import httpx
from shapely.geometry import Point

from app.domain.hydrography import ModeledDepthCell
from app.domain.marine import MarineFamily, ProviderBatch, ProviderUnavailable
from app.infrastructure.marine.cancellation import cancellation_safe

logger = logging.getLogger(__name__)
PROVIDER_ID = "emodnet-dtm-2024"
DATASET_URL = "https://erddap.emodnet.eu/erddap/griddap/bathymetry_dtm_2024"
DOI = "https://doi.org/10.12770/cf51df64-56f9-4a99-b1aa-36b8d7b743a1"
LAT_ORIGIN = 15.000520833333333
LON_ORIGIN = -35.99947916666667
LAT_STEP = 0.0010416666666657431
LON_STEP = 0.001041666666666261
LAT_SIZE = 72000
LON_SIZE = 75840
MAX_CELLS = 64
MAX_BODY = 256 * 1024
REQUEST_DEADLINE = 10
VARIABLES = ("elevation", "value_count", "interpolation_flag", "cdi_index")
CSV_HEADER = ("latitude", "longitude", *VARIABLES)


class EmodnetUnavailable(ProviderUnavailable):
    def __init__(self, reason):
        self.reason = reason
        super().__init__("EMODnet " + reason)


@dataclass(frozen=True)
class GridSelection:
    latitudes: range
    longitudes: range

    @property
    def count(self):
        return len(self.latitudes) * len(self.longitudes)

    @property
    def query(self):
        def axis(indices):
            return f"[{indices.start}:{indices.step}:{indices[-1]}]"

        dims = axis(self.latitudes) + axis(self.longitudes)
        return ",".join(variable + dims for variable in VARIABLES)


def grid_selection(tile):
    """Global, nested strides. Ownership: west <= lon < east, south < lat <= north.

    No neighbour buffer: each native cell belongs to exactly one XYZ tile.
    At max source zoom 16 Mapbox overzooms the same cells without new samples.
    """
    if tile.z < 12:
        return None
    stride = {12: 32, 13: 16, 14: 4, 15: 2}.get(tile.z, 1)
    w, s, e, n = tile.bounds

    def axis(low, high, origin, step, size, latitude=False):
        if latitude:
            first = math.floor((low - origin) / step) + 1
            last = math.floor((high - origin) / step)
        else:
            first = math.ceil((low - origin) / step)
            last = math.ceil((high - origin) / step) - 1
        first = max(0, first)
        last = min(size - 1, last)
        first = ((first + stride - 1) // stride) * stride
        return range(first, max(first, last + 1), stride)

    selection = GridSelection(
        axis(s, n, LAT_ORIGIN, LAT_STEP, LAT_SIZE, latitude=True),
        axis(w, e, LON_ORIGIN, LON_STEP, LON_SIZE),
    )
    if not selection.count:
        return None
    if selection.count > MAX_CELLS:
        raise EmodnetUnavailable("cell-limit")
    return selection


def depth_label(depth):
    """Whole metres, half up; a sub-metre cell is '<1', never a false zero."""
    if depth < 1:
        return "<1"
    return str(Decimal(str(depth)).quantize(Decimal("1"), rounding=ROUND_HALF_UP))


def parse_cells(body, selection):
    """Require the complete requested lattice, even when elevation is missing."""
    if len(body) > MAX_BODY:
        raise EmodnetUnavailable("body-limit")
    if selection.count > MAX_CELLS:
        raise EmodnetUnavailable("cell-limit")
    try:
        rows = csv.reader(io.StringIO(body.decode("utf-8")), strict=True)
        if tuple(next(rows)) != CSV_HEADER:
            raise ValueError("header")
        if next(rows) != ["degrees_north", "degrees_east", "m", "", "", ""]:
            raise ValueError("units")
        seen, features = set(), []

        def optional_int(raw, sentinel, upper=None):
            if raw in {"", "NaN", str(sentinel)}:
                return None
            value = int(raw)
            if value < 0 or (upper is not None and value > upper):
                raise ValueError("quality range")
            return value

        for row in rows:
            if len(row) != len(CSV_HEADER) or len(seen) >= selection.count:
                raise ValueError("row count/shape")
            lat, lon = float(row[0]), float(row[1])
            i = round((lat - LAT_ORIGIN) / LAT_STEP)
            j = round((lon - LON_ORIGIN) / LON_STEP)
            if (
                i not in selection.latitudes
                or j not in selection.longitudes
                or abs(lat - (LAT_ORIGIN + i * LAT_STEP)) > 1e-9
                or abs(lon - (LON_ORIGIN + j * LON_STEP)) > 1e-9
                or (i, j) in seen
            ):
                raise ValueError("unexpected/duplicate coordinate")
            seen.add((i, j))
            elevation = float(row[2]) if row[2] else math.nan
            count = optional_int(row[3], -1, 2147483646)
            flag = optional_int(row[4], 127, 1)
            cdi = optional_int(row[5], -1, 2147483647)
            if not math.isfinite(elevation) or elevation >= 0:
                continue
            identity = f"{PROVIDER_ID}:{i}:{j}"
            features.append(
                ModeledDepthCell(
                    id=identity,
                    source="EMODnet",
                    source_id=f"bathymetry_dtm_2024:{i}:{j}",
                    source_priority=100,
                    geometry=Point(lon, lat),
                    value_original=elevation,
                    unit_original="m",
                    value_m=-elevation,
                    vertical_datum="LAT",
                    sounding_datum="LAT",
                    datum_reference=DATASET_URL + ".das",
                    derivation="modeled_grid_cell",
                    source_geometry_type="GridCell",
                    license="CC-BY-4.0",
                    provenance=(DOI,),
                    grid_lat_index=i,
                    grid_lon_index=j,
                    interpolation_flag=flag,
                    value_count=count,
                    cdi_index=cdi,
                )
            )
        if len(seen) != selection.count:
            raise ValueError("incomplete grid")
        return tuple(features)
    except (ValueError, OverflowError, UnicodeError, csv.Error, StopIteration) as exc:
        raise EmodnetUnavailable("malformed-csv") from exc


class EmodnetDepthProvider:
    id = PROVIDER_ID

    def __init__(self, transport=None, *, interval=0.25):
        self._client = httpx.AsyncClient(
            transport=transport,
            timeout=httpx.Timeout(6, connect=2, pool=2),
            limits=httpx.Limits(max_connections=2, max_keepalive_connections=2),
            follow_redirects=False,
            headers={
                "User-Agent": "NoWave/1.0 marine display (https://no-wave.fr)",
                "Cache-Control": "no-store",
            },
        )
        self._semaphore = asyncio.Semaphore(2)
        self._gate = asyncio.Lock()
        self._interval = interval
        self._next_request = 0.0
        self._cooldown = 0.0
        # Aggregate numbers only; no response bodies or cell cache.
        self.metrics = {"requests": 0, "bytes": 0}

    def covers(self, tile, family):
        w, s, e, n = tile.bounds
        return family == MarineFamily.SOUNDINGS and e > -36 and w < 43 and n > 15

    async def close(self):
        await self._client.aclose()

    async def fetch(self, tile, family):
        if family != MarineFamily.SOUNDINGS:
            return ProviderBatch()
        selection = grid_selection(tile)
        if selection is None:
            return ProviderBatch()
        url = DATASET_URL + ".csv?" + quote(selection.query, safe=",:")
        started = time.monotonic()
        try:
            # Keep the asyncio deadline in the parent: its raw cancellation is
            # translated before it can interrupt the child's HTTP cleanup.
            async with asyncio.timeout(REQUEST_DEADLINE):
                body = await cancellation_safe(lambda: self._read(url))
            features = parse_cells(body, selection)
            logger.info(
                "EMODnet tile=%s/%s/%s cells=%s marine=%s bytes=%s ms=%.1f",
                tile.z,
                tile.x,
                tile.y,
                selection.count,
                len(features),
                len(body),
                (time.monotonic() - started) * 1000,
            )
            return ProviderBatch(features)
        except (TimeoutError, httpx.TimeoutException) as exc:
            self._cooldown = time.monotonic() + 5
            raise EmodnetUnavailable("timeout") from exc
        except httpx.HTTPError as exc:
            self._cooldown = time.monotonic() + 5
            raise EmodnetUnavailable("transport") from exc
        except ValueError as exc:
            raise EmodnetUnavailable("malformed-http") from exc

    async def _read(self, url):
        async with self._semaphore:
            async with self._gate:
                if self._cooldown > time.monotonic():
                    raise EmodnetUnavailable("cooldown")
                delay = self._next_request - time.monotonic()
                if delay > 0:
                    await asyncio.sleep(delay)
                if self._cooldown > time.monotonic():
                    raise EmodnetUnavailable("cooldown")
                self._next_request = time.monotonic() + self._interval
            async with self._client.stream("GET", url) as response:
                self.metrics["requests"] += 1
                if response.status_code in {429, 503}:
                    try:
                        retry = float(response.headers.get("retry-after", "30"))
                    except ValueError:
                        retry = 30
                    self._cooldown = time.monotonic() + max(30, min(120, retry))
                if response.status_code != 200:
                    raise EmodnetUnavailable(f"http-{response.status_code}")
                length = response.headers.get("content-length")
                if length is not None and int(length) > MAX_BODY:
                    raise EmodnetUnavailable("body-limit")
                body = bytearray()
                async for chunk in response.aiter_bytes(chunk_size=4096):
                    self.metrics["bytes"] += len(chunk)
                    if len(body) + len(chunk) > MAX_BODY:
                        raise EmodnetUnavailable("body-limit")
                    body.extend(chunk)
        return body
