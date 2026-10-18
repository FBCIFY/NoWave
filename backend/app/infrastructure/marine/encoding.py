"""MVT presentation contract, preserving existing Flutter source-layer names."""

import hashlib
import json

import mapbox_vector_tile
from shapely import get_dimensions
from shapely.geometry import (
    GeometryCollection,
    MultiLineString,
    MultiPolygon,
    MultiPoint,
    box,
)
from shapely.ops import transform

from app.domain.marine import MarineFamily, SeamarkFeature
from app.domain.marine_tile import project


def clip_geometry(geometry, clip):
    """Discard tangential lower-dimensional remnants unsupported by MVT.

    A valid polygon/line may become a GeometryCollection after clipping. Keep
    its surfaces/lines without turning a touching boundary into a new object.
    """
    clipped = geometry.intersection(clip)
    dimension = get_dimensions(geometry)
    if clipped.geom_type != "GeometryCollection":
        return clipped if get_dimensions(clipped) == dimension else GeometryCollection()
    pending, parts = list(clipped.geoms), []
    while pending:
        part = pending.pop()
        if part.geom_type.startswith("Multi") or part.geom_type == "GeometryCollection":
            pending.extend(part.geoms)
        elif get_dimensions(part) == dimension and not part.is_empty:
            parts.append(part)
    if not parts:
        return GeometryCollection()
    if len(parts) == 1:
        return parts[0]
    return (
        MultiPolygon(parts)
        if dimension == 2
        else MultiLineString(parts)
        if dimension == 1
        else MultiPoint(parts)
    )


def properties(feature):
    result = {
        k: v for k, v in vars(feature).items() if k != "geometry" and v is not None
    }
    for k, value in result.items():
        if isinstance(value, tuple):
            result[k] = json.dumps(value, separators=(",", ":"))
    return result


def encode_tile(tile, family, features):
    if family in {MarineFamily.CONTOURS, MarineFamily.SOUNDINGS, MarineFamily.HAZARDS}:
        from app.infrastructure.marine.hydro_encoding import encode_hydro_tile

        return encode_hydro_tile(tile, family, features)
    bounds = tile.mercator_bounds
    span = bounds[2] - bounds[0]
    clip = box(*bounds).buffer(span * 64 / 4096)
    layers = (
        {"seamark": []}
        if family == MarineFamily.SEAMARKS
        else {
            name: []
            for name in (
                "port_infrastructure",
                "water_polygons",
                "pier_lines",
                "pier_polygons",
            )
        }
    )
    for feature in features:
        geometry = clip_geometry(transform(project, feature.geometry), clip)
        if geometry.is_empty:
            continue
        props = properties(feature)
        identifier = int.from_bytes(hashlib.sha256(feature.id.encode()).digest()[:6])

        def add(layer, geom, extra=None):
            if not geom.is_empty:
                layers[layer].append(
                    {
                        "id": identifier,
                        "geometry": geom,
                        "properties": {**props, **(extra or {})},
                    }
                )

        if isinstance(feature, SeamarkFeature):
            add("seamark", geometry)
            continue
        add("port_infrastructure", geometry)
        kind = feature.infrastructure_type
        polygons = geometry.geom_type in {"Polygon", "MultiPolygon"}
        lines = geometry.geom_type in {"LineString", "MultiLineString"}
        if kind in {"breakwater", "groyne"} and (polygons or lines):
            add(
                "pier_lines",
                geometry.boundary if polygons else geometry,
                {"kind": kind},
            )
        elif kind == "dock" and polygons:
            add("water_polygons", geometry, {"kind": "dock"})
        elif kind in {"pier", "pontoon"} and (polygons or lines):
            add(
                "pier_polygons" if polygons else "pier_lines",
                geometry,
                {"kind": "pier"},
            )
        elif kind == "quay" and polygons:
            # The existing pale marine-structure surface is appropriate to a
            # real quay footprint. A quay LINE has no existing matching style.
            add("pier_polygons", geometry, {"kind": "quay"})
    return mapbox_vector_tile.encode(
        [{"name": name, "features": values} for name, values in layers.items()],
        default_options={
            "quantize_bounds": bounds,
            "extents": 4096,
            "check_winding_order": True,
        },
    )
