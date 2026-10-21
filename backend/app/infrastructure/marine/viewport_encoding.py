"""Bounded WGS84 snapshots for persistent marine rendering, without MVT rounding."""

import json
import math

from shapely.geometry import mapping, box, LineString

from app.domain.hydrography import DepthContour, Sounding, ModeledDepthCell
from app.domain.marine import MarineFamily, ProviderUnavailable
from app.infrastructure.marine.encoding import clip_geometry, properties
from app.infrastructure.marine.hydro_encoding import MIN_ZOOM
from app.infrastructure.marine.hydro_normalization import select_soundings

MAX_BYTES = 4 * 1024 * 1024
MAX_FEATURES = 6000


def encode_viewport_tile(tile, family, features):
    if tile.z < (6 if family == MarineFamily.HARBOURS else MIN_ZOOM.get(family, 10)):
        features = []
    if family == MarineFamily.SOUNDINGS:
        features = list(features)
        cells = [f for f in features if isinstance(f, ModeledDepthCell)]
        samples = [f for f in features if not isinstance(f, ModeledDepthCell)]
        features = cells + select_soundings(samples, max(14, tile.z))
    n = 1 << tile.z
    w, e = tile.x / n * 360 - 180, (tile.x + 1) / n * 360 - 180
    north = math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * tile.y / n))))
    south = math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * (tile.y + 1) / n))))
    clip = box(w, south, e, north)
    unowned_edges = LineString([(w, south), (e, south), (e, north)])
    encoded = []
    for feature in sorted(features, key=lambda f: f.id):
        geometry = clip_geometry(feature.geometry, clip)
        if isinstance(feature, DepthContour):
            geometry = geometry.difference(unowned_edges)
        if geometry.is_empty:
            continue
        # Half-open point ownership prevents duplicates on tile boundaries.
        if geometry.geom_type == "Point":
            if not (w <= geometry.x < e and south < geometry.y <= north):
                continue
        props = properties(feature)
        if isinstance(feature, (DepthContour, Sounding)):
            props["depth_label"] = (
                format(feature.value_m, ".12f").rstrip("0").rstrip(".")
            )
            if props["depth_label"] == "-0":
                props["depth_label"] = "0"
            if isinstance(feature, ModeledDepthCell):
                from app.infrastructure.marine.emodnet_depths import depth_label

                props["depth_label"] = depth_label(feature.value_m)
        # The original source id remains a property. Disjoint contour fragments
        # have a stable tile-qualified rendering id; no name/proximity matching.
        identifier = (
            f"{feature.id}@{tile.z}/{tile.x}/{tile.y}"
            if isinstance(feature, DepthContour)
            else feature.id
        )
        encoded.append(
            dict(
                type="Feature",
                id=identifier,
                properties=props,
                geometry=mapping(geometry),
            )
        )
        if len(encoded) > MAX_FEATURES:
            raise ProviderUnavailable("Marine snapshot feature budget exceeded")
    body = json.dumps(
        dict(type="FeatureCollection", features=encoded),
        allow_nan=False,
        separators=(",", ":"),
    ).encode()
    if len(body) > MAX_BYTES:
        raise ProviderUnavailable("Marine snapshot byte budget exceeded")
    return body
