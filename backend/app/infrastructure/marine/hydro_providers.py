"""Official objects and published vector contours; never reads a raster PNG."""

import json
from dataclasses import replace

from shapely.geometry import GeometryCollection, box, shape
from shapely.ops import unary_union

from app.domain.marine import MarineFamily, ProviderBatch, ProviderUnavailable
from app.infrastructure.marine.encoding import clip_geometry
from app.infrastructure.marine.hydro_normalization import normalize_hydro
from app.infrastructure.marine.providers import COVERAGE, DATA, collect

HYDRO_FAMILIES = {MarineFamily.CONTOURS, MarineFamily.SOUNDINGS, MarineFamily.HAZARDS}
LAYERS = json.loads((DATA / "hydro_layers.json").read_text())


class ShomHazardProvider:
    id = "shom-hazards"
    url = "https://services.data.shom.fr/INSPIRE/wfs"

    def __init__(self, http):
        self.http = http

    def covers(self, tile, family):
        return family == MarineFamily.HAZARDS and COVERAGE["shom"].intersects(
            box(*tile.query_bounds)
        )

    async def fetch(self, tile, family):
        async def layer(code):
            body = await self.http.get(
                self.url,
                params=dict(
                    service="WFS",
                    version="1.0.0",
                    request="GetFeature",
                    typeName=f"EPAVES_BDD_WFS:{code}",
                    outputFormat="json",
                    srsName="EPSG:4326",
                    # Default native CRS for EPAVES is 3857: explicit BBOX CRS is essential.
                    bbox=",".join(map(str, tile.parent().query_bounds)) + ",EPSG:4326",
                    maxFeatures=2000,
                ),
            )
            data = json.loads(body)
            if data.get(
                "numberMatched", data.get("totalFeatures", len(data["features"]))
            ) > len(data["features"]):
                raise ProviderUnavailable("Truncated Shom hazards")
            return data["features"]

        results, failures = await collect(
            (code, layer(code)) for code in ("wrecks", "obstrn")
        )
        features = []
        for code, raw in results:
            for f in raw:
                try:
                    # The published obstrn schema does not identify a rock subtype.
                    features.extend(
                        normalize_hydro(
                            f,
                            "wreck" if code == "wrecks" else "obstruction",
                            source="shom",
                            dataset=f"EPAVES_BDD_WFS:{code}",
                        )
                    )
                except (ValueError, TypeError, KeyError):
                    failures.append(code + ":invalid-feature")
        return ProviderBatch(tuple(features), tuple(sorted(set(failures))))


class EmodnetContourProvider:
    id = "emodnet-contours"
    url = "https://ows.emodnet-bathymetry.eu/wfs"

    def __init__(self, http):
        self.http = http

    def covers(self, tile, family):
        # Published WFS bounds. NOAA-covered areas use the ENC provider.
        return (
            family == MarineFamily.CONTOURS
            and box(-70.5, 11.001, 43.002, 86.662).intersects(tile.polygon)
            and not COVERAGE["noaa"].intersects(tile.polygon)
        )

    async def fetch(self, tile, family):
        body = await self.http.get(
            self.url,
            params=dict(
                service="WFS",
                version="1.0.0",
                request="GetFeature",
                typeName="emodnet:contours",
                outputFormat="application/json",
                srsName="EPSG:4326",
                bbox=",".join(map(str, tile.parent().query_bounds)) + ",EPSG:4326",
                maxFeatures=2000,
            ),
        )
        data = json.loads(body)
        if data.get(
            "numberMatched", data.get("totalFeatures", len(data["features"]))
        ) > len(data["features"]):
            raise ProviderUnavailable("Truncated EMODnet contours")
        features = [
            f
            for raw in data["features"]
            for f in normalize_hydro(
                raw,
                "depth_contour",
                source="emodnet",
                dataset="contours-2022",
                priority=20,
            )
        ]
        return ProviderBatch(tuple(features))


class NoaaHydroProvider:
    id = "noaa-hydro"
    base_url = "https://encdirect.noaa.gov/arcgis/rest/services/encdirect"

    def __init__(self, http):
        self.http = http

    def covers(self, tile, family):
        return family in HYDRO_FAMILIES and COVERAGE["noaa"].intersects(
            box(*tile.query_bounds)
        )

    async def _query(self, url, tile, *, sounding=False):
        features = []
        for offset in range(0, 4000, 1000):
            params = dict(
                f="geojson",
                where="1=1",
                outFields="*",
                outSR=4326,
                geometry=",".join(map(str, tile.query_bounds)),
                geometryType="esriGeometryEnvelope",
                inSR=4326,
                spatialRel="esriSpatialRelIntersects",
                returnGeometry="true",
                returnZ="true" if sounding else "false",
                resultRecordCount=1000,
                resultOffset=offset,
            )
            # Coverage layers do not share an OID field name (Approach uses
            # APPROACH.M_COVR.FID); ArcGIS defaults pagination to its native OID.
            body = await self.http.get(url, params=params)
            data = json.loads(body)
            features.extend(data["features"])
            if not data.get("exceededTransferLimit") and len(data["features"]) < 1000:
                return features
        raise ProviderUnavailable("NOAA hydro feature limit reached")

    async def fetch(self, tile, family):
        query_tile = tile.parent(14 if family == MarineFamily.SOUNDINGS else 12)
        kinds = (
            {"depth_contour"}
            if family == MarineFamily.CONTOURS
            else {"sounding"}
            if family == MarineFamily.SOUNDINGS
            else {"rock", "wreck", "obstruction"}
        )

        # ENC scale selection is a coverage operation, not a proximity merge.
        # Retain coarser geometry outside the areas of more detailed cells.
        async def coverage(rank):
            return await self._query(
                f"{self.base_url}/enc_coverage/MapServer/{rank - 1}/query",
                query_tile.parent(),
            )

        cover_results, failures = await collect(
            (str(rank), coverage(rank)) for rank in range(2, 7)
        )
        masks = {}
        covered = GeometryCollection()
        region = box(*query_tile.query_bounds)
        for rank, raw in sorted(cover_results, key=lambda item: -int(item[0])):
            geometries = []
            for f in raw:
                # CATCOV=2 explicitly denotes no coverage, not a finer chart.
                props = {k.lower(): v for k, v in f.get("properties", {}).items()}
                if str(props.get("catcov", "1")) not in {
                    "1",
                    "1.0",
                    "coverage available",
                }:
                    continue
                geometry = shape(f["geometry"]) if f.get("geometry") else None
                if geometry is None or not geometry.is_valid:
                    failures.append(rank + ":invalid-coverage")
                    continue
                geometries.append(geometry)
            if not geometries:
                continue
            mask = unary_union(geometries).intersection(region)
            masks[int(rank)] = mask.difference(covered)
            covered = covered.union(mask)
        layers = [
            l
            for l in LAYERS
            if l["kind"] in kinds | {"sounding_datum"}
            and l["rank"] in masks
            and not masks[l["rank"]].is_empty
            and box(*l["bounds"]).intersects(region)
        ]
        indexed = {f"{l['scale']}:{l['layer']}": l for l in layers}
        results, errors = await collect(
            (
                key,
                self._query(
                    f"{self.base_url}/enc_{l['scale']}/MapServer/{l['layer']}/query",
                    query_tile,
                    sounding=l["kind"] == "sounding",
                ),
            )
            for key, l in indexed.items()
        )
        failures.extend(errors)
        datums = {}
        for key, raw in results:
            layer = indexed[key]
            if layer["kind"] != "sounding_datum":
                continue
            for f in raw:
                p = {k.lower(): v for k, v in f["properties"].items()}
                if p.get("verdat") is None or not p.get("dsnm"):
                    continue
                geometry = shape(f["geometry"]) if f.get("geometry") else None
                if geometry is None or not geometry.is_valid:
                    failures.append(key + ":invalid-datum-area")
                    continue
                datums.setdefault((layer["scale"], p["dsnm"]), []).append(
                    (geometry, str(p["verdat"]), key, str(f["id"]))
                )
        features = []
        for key, raw in results:
            layer = indexed[key]
            if layer["kind"] == "sounding_datum":
                continue
            for f in raw:
                try:
                    for feature in normalize_hydro(
                        f,
                        layer["kind"],
                        source="noaa",
                        dataset=key,
                        scale=layer["scale"],
                        priority=100 + layer["rank"],
                    ):
                        geometry = clip_geometry(feature.geometry, masks[layer["rank"]])
                        if not geometry.is_empty:
                            feature = replace(feature, geometry=geometry)
                            # A published datum area is usable only in the same
                            # ENC cell and scale, covering the complete fragment.
                            cell = f["properties"].get("DSNM")
                            matches = [
                                d
                                for d in datums.get((layer["scale"], cell), [])
                                if d[0].covers(geometry)
                            ]
                            if (
                                feature.vertical_datum is None
                                and matches
                                and len({d[1] for d in matches}) == 1
                            ):
                                datum = sorted(matches, key=lambda d: (d[2], d[3]))[0]
                                feature = replace(
                                    feature,
                                    vertical_datum=datum[1],
                                    sounding_datum=datum[1],
                                    datum_reference=f"{self.base_url}/enc_{layer['scale']}/MapServer/{datum[2].split(':')[1]}",
                                    provenance=(
                                        *feature.provenance,
                                        f"noaa:{datum[2]}:{datum[3]}",
                                    ),
                                )
                            features.append(feature)
                except (ValueError, TypeError, KeyError):
                    failures.append(key + ":invalid-feature")
        return ProviderBatch(tuple(features), tuple(sorted(set(failures))))


class NoaaSoundingProvider(NoaaHydroProvider):
    """Original ENC soundings outside EMODnet, on a disk-free HTTP client."""

    id = "noaa-soundings"
    min_zoom = 12

    def covers(self, tile, family):
        return family == MarineFamily.SOUNDINGS and super().covers(tile, family)

    async def fetch(self, tile, family):
        if tile.z < self.min_zoom or family != MarineFamily.SOUNDINGS:
            return ProviderBatch()
        return await super().fetch(tile, family)
