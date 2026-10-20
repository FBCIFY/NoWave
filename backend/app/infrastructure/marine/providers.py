import asyncio
import json
from dataclasses import replace
from pathlib import Path

import mapbox_vector_tile
from shapely.geometry import box, shape
from shapely.ops import transform

from app.domain.marine import (
    BUOY_TYPES,
    SEAMARK_TYPES,
    MarineFamily,
    PortInfrastructureFeature,
    ProviderBatch,
    SeamarkFeature,
)
from app.domain.marine_tile import Tile, unproject
from app.infrastructure.marine.http import MarineHTTP
from app.domain.marine import ProviderUnavailable
from app.infrastructure.marine.normalization import (
    CLASSES,
    attach_topmark,
    attach_light,
    lighthouse_structure,
    osm_light_attributes,
    attributes,
    infrastructure,
    seamark,
    text,
)

DATA = Path(__file__).with_name("data")
COVERAGE = {
    k: shape(v) for k, v in json.loads((DATA / "coverage.json").read_text()).items()
}
NOAA_LAYERS = json.loads((DATA / "noaa_layers.json").read_text())


async def collect(jobs):
    """One provider has a wall-clock budget, including semaphore queue time."""
    tasks = {asyncio.create_task(job): name for name, job in jobs}
    if not tasks:
        return [], []
    done, pending = await asyncio.wait(tasks, timeout=12)
    for task in pending:
        task.cancel()
    await asyncio.gather(*pending, return_exceptions=True)
    results, failures = [], [tasks[t] + ":deadline" for t in pending]
    for task in sorted(done, key=lambda t: tasks[t]):
        try:
            results.append((tasks[task], task.result()))
        except (ProviderUnavailable, ValueError, KeyError) as exc:
            failures.append(tasks[task] + ":" + type(exc).__name__)
    return results, sorted(failures)


class OpenWatersProvider:
    id = "openwaters"

    def __init__(self, http: MarineHTTP):
        self.http = http
        self.url = "https://tiles.openwaters.io/seamap/{z}/{x}/{y}.pbf"

    def covers(self, tile, family):
        return family == MarineFamily.SEAMARKS

    async def fetch(self, tile: Tile, family):
        content = await self.http.get(
            self.url.format(z=tile.z, x=tile.x, y=tile.y), ttl=86400, vector_tile=True
        )
        layers = mapbox_vector_tile.decode(content) if content else {}
        layer = layers.get("seamark", {})
        extent = layer.get("extent", 4096)
        west, south, east, north = tile.mercator_bounds
        span = east - west
        features = []
        for f in layer.get("features", []):
            p = f["properties"]
            feature_type = p.get("type")
            if feature_type in {"light_major", "light_minor"}:
                feature_type = "light"
            # Do not promote major lights or generic towers to lighthouses.
            if feature_type not in SEAMARK_TYPES or f["geometry"]["type"] != "Point":
                continue
            geometry = transform(
                lambda x, y: unproject(
                    west + x * span / extent, south + y * span / extent
                ),
                shape(f["geometry"]),
            )
            # Upstream's buffered features may cross the antimeridian.
            if not (-180 <= geometry.x <= 180):
                continue
            sid = text(p.get("osm_id")) or text(f.get("id"))
            if not sid:
                continue
            props = {
                k: text(p.get(k))
                for k in (
                    "type",
                    "category",
                    "color",
                    "color_pattern",
                    "shape",
                    "topmark_shape",
                    "topmark_color",
                    "name",
                )
            }
            props["type"] = feature_type
            # The upstream normalized light_range may contain a default of 9 M.
            # Only an explicit source tag is a measured/published range here.
            light = osm_light_attributes(p)
            if feature_type.startswith("beacon_"):
                # Open Waters can synthesize conventional colours/patterns.
                # New fixed marks require actual source tags to qualify them.
                for key, tag in [
                    ("color", "colour"),
                    ("color_pattern", "colour_pattern"),
                ]:
                    if not p.get(f"seamark:{feature_type}:{tag}"):
                        props[key] = ""
            system = {
                "iala-a": "IALA_A",
                "iala-b": "IALA_B",
                "IALA_A": "IALA_A",
                "IALA_B": "IALA_B",
            }.get(
                p.get("navigation_system")
                or p.get("seamark:system")
                or (
                    p.get(f"seamark:{feature_type}:system")
                    if feature_type.startswith("beacon_")
                    else None
                ),
                "",
            )
            # Preserve real lateral colors even when OSM has no system tag;
            # don't infer a side or region from a phone's position.
            features.append(
                SeamarkFeature(
                    id=f"openwaters:{sid}",
                    geometry=geometry,
                    source=self.id,
                    source_id=sid,
                    source_priority=10,
                    provenance=(f"openwaters:{sid}",),
                    navigation_system=system,
                    inferred_fields=tuple(
                        key
                        for key, raw in {
                            "shape": f"seamark:{props['type']}:shape",
                        }.items()
                        if p.get(key) and not p.get(raw)
                    ),
                    **props,
                    **light,
                )
            )
        return ProviderBatch(tuple(features))


class ShortbreadProvider:
    id = "osm"

    def __init__(self, http: MarineHTTP, url=None):
        self.http = http
        self.url = (
            url or "https://vector.openstreetmap.org/shortbread_v1/{z}/{x}/{y}.mvt"
        )

    def covers(self, tile, family):
        return family == MarineFamily.PORTS

    async def fetch(self, tile: Tile, family):
        content = await self.http.get(
            self.url.format(z=tile.z, x=tile.x, y=tile.y),
            ttl=604800,
            osm=True,
            vector_tile=True,
        )
        layers = mapbox_vector_tile.decode(content) if content else {}
        west, south, east, north = tile.mercator_bounds
        span = east - west
        features = []
        for name in ("water_polygons", "pier_lines", "pier_polygons"):
            layer = layers.get(name, {})
            for f in layer.get("features", []):
                p = f["properties"]
                kind = p.get("kind") if name != "pier_polygons" else "pier"
                if kind not in {"dock", "pier", "breakwater", "groyne"}:
                    continue
                extent = layer.get("extent", 4096)
                geometry = transform(
                    lambda x, y: unproject(
                        west + x * span / extent, south + y * span / extent
                    ),
                    shape(f["geometry"]),
                )
                geometry = geometry.intersection(
                    box(-180, -85.05112878, 180, 85.05112878)
                )
                if geometry.is_empty or not geometry.is_valid:
                    continue
                # Shortbread currently omits OSM IDs in these layers. A geometry
                # digest identifies a tile fragment; never claim it is an OSM ID.
                import hashlib

                sid = (
                    f"{name}:{tile.z}/{tile.x}/{tile.y}:"
                    + hashlib.sha256(geometry.wkb).hexdigest()[:20]
                )
                features.append(
                    PortInfrastructureFeature(
                        id=f"osm:{sid}",
                        geometry=geometry,
                        source=self.id,
                        source_id=sid,
                        source_priority=10,
                        provenance=(f"osm:{sid}",),
                        name=text(p.get("name")),
                        infrastructure_type=kind,
                    )
                )
        return ProviderBatch(tuple(features))


class ShomProvider:
    id = "shom"
    url = "https://services.data.shom.fr/INSPIRE/wfs"

    def __init__(self, http: MarineHTTP):
        self.http = http

    def covers(self, tile, family):
        return family == MarineFamily.SEAMARKS and COVERAGE[self.id].intersects(
            box(*tile.query_bounds)
        )

    async def _layer(self, tile, code):
        # SHOM's gateway rejects comma-separated typeNames with MissingRights;
        # WFS 1.0 single types + EPSG:4326 have verified lon/lat ordering.
        content = await self.http.get(
            self.url,
            params={
                "service": "WFS",
                "version": "1.0.0",
                "request": "GetFeature",
                "typeName": f"BALISAGE_BDD_WFS:{code}",
                "outputFormat": "json",
                "srsName": "EPSG:4326",
                "bbox": ",".join(map(str, tile.query_bounds)),
                "maxFeatures": 2000,
            },
        )
        data = json.loads(content)
        if len(data["features"]) >= 2000:
            raise ProviderUnavailable("SHOM feature limit reached")
        return data["features"]

    async def fetch(self, tile, family):
        results, failures = await collect(
            (code, self._layer(tile.parent(), code)) for code in (*CLASSES, "topmar")
        )
        layers = dict(results)
        tops = {attributes(f).get("inspireid"): f for f in layers.get("topmar", [])}
        lights = {attributes(f).get("inspireid"): f for f in layers.get("lights", [])}
        features = []
        for code, feature_type in CLASSES.items():
            for f in layers.get(code, []):
                try:
                    if feature_type == "lighthouse" and not lighthouse_structure(f):
                        continue
                    buoy = seamark(
                        f, feature_type, source=self.id, dataset=code, priority=100
                    )
                    top = tops.get(attributes(f).get("topmar"))
                    if top:
                        buoy = attach_topmark(buoy, top)
                    light = lights.get(attributes(f).get("lights"))
                    if light:
                        buoy = attach_light(buoy, light)
                    features.append(buoy)
                except (ValueError, KeyError, TypeError):
                    failures.append(code + ":invalid-feature")
        return ProviderBatch(tuple(features), tuple(failures))


class NoaaProvider:
    id = "noaa"
    base_url = "https://encdirect.noaa.gov/arcgis/rest/services/encdirect"

    def __init__(self, http: MarineHTTP):
        self.http = http

    def covers(self, tile, family):
        return family in {MarineFamily.SEAMARKS, MarineFamily.PORTS} and COVERAGE[
            self.id
        ].intersects(box(*tile.query_bounds))

    async def _layer(self, tile, layer):
        url = f"{self.base_url}/enc_{layer['scale']}/MapServer/{layer['layer']}/query"
        features = []
        for offset in (0, 1000):
            content = await self.http.get(
                url,
                params={
                    "f": "geojson",
                    "where": "1=1",
                    "outFields": "*",
                    "outSR": 4326,
                    "geometry": ",".join(map(str, tile.query_bounds)),
                    "geometryType": "esriGeometryEnvelope",
                    "inSR": 4326,
                    "spatialRel": "esriSpatialRelIntersects",
                    "returnGeometry": "true",
                    "resultRecordCount": 1000,
                    "resultOffset": offset,
                },
            )
            data = json.loads(content)
            features.extend(data["features"])
            if not data.get("exceededTransferLimit") and len(data["features"]) < 1000:
                return features
        raise ProviderUnavailable("NOAA feature limit reached")

    async def fetch(self, tile, family):
        query_tile = tile.parent()
        kinds = (
            SEAMARK_TYPES | {"topmark"}
            if family == MarineFamily.SEAMARKS
            else {"construction", "dock"}
        )
        layers = [
            l
            for l in NOAA_LAYERS
            if l["kind"] in kinds
            and box(*l["bounds"]).intersects(box(*query_tile.query_bounds))
        ]
        # Preserve the request budget of the existing buoy/topmark classes.
        layers.sort(key=lambda l: l["kind"] not in BUOY_TYPES | {"topmark"})
        indexed = {f"{l['scale']}:{l['layer']}": l for l in layers}
        results, failures = await collect(
            (key, self._layer(query_tile, layer)) for key, layer in indexed.items()
        )
        tops, lights = {}, {}
        for key, features in results:
            layer = indexed[key]
            if layer["kind"] == "topmark":
                for f in features:
                    # Exact collocation AND same ENC cell. No nearest topmark guess.
                    p = attributes(f)
                    tops[
                        (
                            layer["scale"],
                            p.get("dsnm"),
                            tuple(f["geometry"]["coordinates"]),
                        )
                    ] = f
            if layer["kind"] == "light":
                for f in features:
                    p = attributes(f)
                    lights.setdefault(
                        (
                            layer["scale"],
                            p.get("dsnm"),
                            tuple(f["geometry"]["coordinates"]),
                        ),
                        [],
                    ).append(f)
        features = []
        for key, raw in results:
            layer = indexed[key]
            if layer["kind"] == "topmark":
                continue
            for f in raw:
                try:
                    if layer["kind"] == "lighthouse" and not lighthouse_structure(f):
                        continue
                    options = dict(
                        source=self.id,
                        dataset=key,
                        priority=100 + layer["rank"],
                        scale=layer["scale"],
                    )
                    if family == MarineFamily.SEAMARKS:
                        result = seamark(f, layer["kind"], **options)
                        p = attributes(f)
                        top = tops.get(
                            (
                                layer["scale"],
                                p.get("dsnm"),
                                tuple(f["geometry"]["coordinates"]),
                            )
                        )
                        if top:
                            result = attach_topmark(result, top)
                        linked = lights.get(
                            (
                                layer["scale"],
                                p.get("dsnm"),
                                tuple(f["geometry"]["coordinates"]),
                            ),
                            [],
                        )
                        # Several sectors at one point are not one combined light.
                        if layer["kind"] != "light" and len(linked) == 1:
                            result = attach_light(result, linked[0])
                    else:
                        result = infrastructure(f, layer["kind"], **options)
                    # DSNM is genuine chart-cell provenance, not an object identity.
                    dsnm = text(attributes(f).get("dsnm"))
                    result = replace(
                        result,
                        provenance=(*result.provenance, f"noaa:cell:{dsnm}")
                        if dsnm
                        else result.provenance,
                    )
                    features.append(result)
                except (ValueError, KeyError, TypeError):
                    failures.append(key + ":invalid-feature")
        return ProviderBatch(tuple(features), tuple(failures))
