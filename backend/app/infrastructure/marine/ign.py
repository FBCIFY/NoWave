"""The verified port subset of IGN BD TOPO construction_lineaire.

`nature=Quai` is an umbrella class. Its detailed category is essential: generic
quays, ramps, jetties, terrestrial flood dykes are not all piers/breakwaters.
"""

import json

from shapely import force_2d
from shapely.geometry import box, shape
from shapely.ops import unary_union

from app.domain.marine import MarineFamily, PortInfrastructureFeature, ProviderBatch
from app.domain.marine import ProviderUnavailable
from app.infrastructure.marine.normalization import text

# Official BD TOPO extent: mainland + DROM + SPM, St Martin, St Barthélemy.
# Conservative product-territory routing hints. Independent of SHOM sea areas:
# an inland port or a quay behind straight baselines is still eligible.
_TERRITORIES = unary_union(
    [
        box(-6, 41, 10, 52),
        box(-62.1, 14, -60.7, 16.7),
        box(-63.3, 17.7, -62.6, 18.3),
        box(-54.7, 2, -51.4, 6),
        box(-56.6, 46.6, -56, 47.3),
        box(55, -21.5, 56, -20.8),
        box(44.9, -13.1, 45.5, -12.4),
    ]
)


class IgnPortProvider:
    id = "ign"
    url = "https://data.geopf.fr/wfs/ows"

    def __init__(self, http):
        self.http = http

    def covers(self, tile, family):
        return family == MarineFamily.PORTS and _TERRITORIES.intersects(
            box(*tile.query_bounds)
        )

    async def fetch(self, tile, family):
        w, s, e, n = tile.parent().query_bounds
        content = await self.http.get(
            self.url,
            params={
                "service": "WFS",
                "version": "2.0.0",
                "request": "GetFeature",
                "typeNames": "BDTOPO_V3:construction_lineaire",
                "srsName": "urn:ogc:def:crs:OGC:1.3:CRS84",
                "outputFormat": "application/json",
                # GeoServer cannot combine BBOX and CQL_FILTER query parameters;
                # use one verified spatial + attribute filter, CRS84 lon/lat.
                "cql_filter": f"BBOX(geometrie,{w},{s},{e},{n},'CRS:84') AND nature='Quai'",
                "count": 2000,
            },
            ttl=86400,
        )
        data = json.loads(content)
        if data.get("numberMatched", 0) == "unknown" or int(
            data.get("numberMatched", len(data["features"]))
        ) > len(data["features"]):
            raise ProviderUnavailable("IGN feature limit reached")
        features, failures = [], []
        for raw in data["features"]:
            p = raw["properties"]
            if p.get("nature") != "Quai" or p.get("etat_de_l_objet") != "En service":
                continue
            detail = text(p.get("nature_detaillee"))
            kind = {
                "Brise-lames": "breakwater",
                "Epi": "groyne",
                "Ponton": "pontoon",
                "Jetée": "jetty",
            }.get(detail, "quay")
            if detail in {
                "Cale",
                "Cale réservée aux secours",
                "Digue",
                "Jetée de dérivation",
                "Pêche au carrelet",
            }:
                kind = "shoreline_construction"  # No matching existing UI semantic.
            try:
                sid = text(p["cleabs"])
                features.append(
                    PortInfrastructureFeature(
                        id=f"ign:{sid}",
                        source=self.id,
                        source_id=sid,
                        source_priority=100,
                        geometry=force_2d(shape(raw["geometry"])),
                        infrastructure_type=kind,
                        name=text(p.get("toponyme")),
                        source_category=detail,
                        source_updated_at=text(p.get("date_modification")),
                        provenance=(f"ign:{sid}",),
                    )
                )
            except (ValueError, KeyError, TypeError):
                failures.append("construction_lineaire:invalid-feature")
        return ProviderBatch(tuple(features), tuple(failures))
