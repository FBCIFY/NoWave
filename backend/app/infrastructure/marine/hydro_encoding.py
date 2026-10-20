"""Independent NoWave MVT layers for lines, depth samples and hazard geometry."""

import hashlib

import mapbox_vector_tile
from shapely.geometry import box
from shapely.ops import transform

from app.domain.hydrography import DepthContour, Sounding, ModeledDepthCell
from app.domain.marine import MarineFamily
from app.domain.marine_tile import project
from app.infrastructure.marine.encoding import clip_geometry, properties
from app.infrastructure.marine.hydro_normalization import select_soundings

LAYER_NAMES = {
    MarineFamily.CONTOURS: "depth_contour",
    MarineFamily.SOUNDINGS: "sounding",
    MarineFamily.HAZARDS: "underwater_hazard",
}
MIN_ZOOM = {
    MarineFamily.CONTOURS: 12,
    MarineFamily.SOUNDINGS: 12,
    MarineFamily.HAZARDS: 12,
}


def encode_hydro_tile(tile, family, features):
    bounds = tile.mercator_bounds
    span = bounds[2] - bounds[0]
    clip = box(*bounds).buffer(span * 64 / 4096)
    if tile.z < MIN_ZOOM[family]:
        features = []
    if family == MarineFamily.SOUNDINGS:
        from app.infrastructure.marine.emodnet_depths import MAX_CELLS

        features = list(features)
        cells = {f.id: f for f in features if isinstance(f, ModeledDepthCell)}
        legacy = [f for f in features if not isinstance(f, ModeledDepthCell)]
        features = [cells[key] for key in sorted(cells)][:MAX_CELLS]
        features += select_soundings(legacy, min(tile.z, 16))
    encoded = []
    for feature in features:
        if isinstance(feature, ModeledDepthCell):
            w, s, e, n = tile.bounds
            if not (w <= feature.geometry.x < e and s < feature.geometry.y <= n):
                continue
        if isinstance(feature, DepthContour) and tile.z < feature.display_minzoom:
            continue
        # No simplification of hazards or samples; quantization is the only
        # positional rounding. Contour simplification is 0.125 source pixel
        # (512px tile); overzoom multiplies this, e.g. 1px at z17 from z14.
        geometry = transform(project, feature.geometry)
        if isinstance(feature, DepthContour):
            geometry = geometry.simplify(span / 4096, preserve_topology=True)
        geometry = clip_geometry(geometry, clip)
        if geometry.is_empty:
            continue
        props = properties(feature)
        if isinstance(feature, (DepthContour, Sounding)):
            # Preserve published decimals; do not round a 1.25m sample to 1.2m.
            props["depth_label"] = (
                format(feature.value_m, ".12f").rstrip("0").rstrip(".")
            )
            if props["depth_label"] == "-0":
                props["depth_label"] = "0"
            if isinstance(feature, ModeledDepthCell):
                from app.infrastructure.marine.emodnet_depths import depth_label

                props["depth_label"] = depth_label(feature.value_m)
        identifier = int.from_bytes(hashlib.sha256(feature.id.encode()).digest()[:6])
        encoded.append(dict(id=identifier, geometry=geometry, properties=props))
    return mapbox_vector_tile.encode(
        {"name": LAYER_NAMES[family], "features": encoded},
        default_options={
            "quantize_bounds": bounds,
            "extents": 4096,
            "check_winding_order": True,
        },
    )
