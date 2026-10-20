"""Adapters for verified NOAA ENC, Shom EPAVES and EMODnet contour fields."""

import json
import math
from dataclasses import replace

from shapely import force_2d
from shapely.geometry import Point

from app.domain.hydrography import DepthContour, Sounding, UnderwaterHazard
from app.infrastructure.marine.normalization import (
    attributes,
    number,
    source_fields,
    text,
)

UNIT_FACTORS = {"m": 1.0, "ft": 0.3048, "fathom": 1.8288}
WATER_LEVEL = {
    "1": "partly_submerged",
    "2": "always_dry",
    "3": "always_submerged",
    "4": "covers_and_uncovers",
    "5": "awash",
    "6": "subject_to_inundation",
    "7": "floating",
}


def depth_values(value, unit):
    try:
        value = float(value)
        if not math.isfinite(value):
            value = None
    except (TypeError, ValueError):
        value = None
    if value is None:
        return dict(value_original=None, unit_original=unit, value_m=None)
    if unit not in UNIT_FACTORS:
        raise ValueError("Unverified depth unit")
    return dict(
        value_original=value, unit_original=unit, value_m=value * UNIT_FACTORS[unit]
    )


def contour_presentation(depth):
    """Select only existing lines: 0 and multiples of 10m major, others minor.

    At z12: major plus published lines >=3m. z13: also >=1m; z14: all.
    This keeps the real 3.6m / 5.4m legacy ENC contours visible at z12 too.
    These are selection thresholds, never fabricated contour values.
    """
    major = depth == 0 or abs(depth / 10 - round(depth / 10)) < 1e-8
    return (
        "major" if major else "minor",
        12 if major or depth >= 3 else 13 if depth >= 1 else 14,
    )


def normalize_hydro(
    feature, kind, *, source, dataset, priority=100, scale="", unit="m"
):
    p = attributes(feature)
    fields = source_fields(
        feature, source=source, dataset=dataset, priority=priority, scale=scale
    )
    geometry = fields["geometry"]
    fields.update(
        geometry=force_2d(geometry),
        source_geometry_type=geometry.geom_type,
        source_attributes=json.dumps(
            feature["properties"], sort_keys=True, separators=(",", ":")
        ),
        vertical_datum=text(p.get("verdat")) or None,
        sounding_datum=text(p.get("sounding_datum")) or None,
        quality=text(p.get("quasou")) or None,
        accuracy=number(p.get("souacc")),
    )
    if source == "emodnet":
        fields.update(derivation="published_dtm_contour_2022", license="CC-BY-4.0")
    if source == "shom":
        fields.update(
            name=text(p.get("nom")),
            quality=text(p.get("precis_bra")) or None,
            horizontal_accuracy=number(p.get("precis_loc")),
            derivation="published_hydrographic_object",
            license="CC-BY-SA-4.0",
            sounding_datum="chart_datum",
            datum_reference="https://services.data.shom.fr/static/specifications/spec_epaves_et_obstructions.pdf",
        )
    if kind == "depth_contour":
        values = depth_values(
            p.get("elevation") if source == "emodnet" else p.get("valdco"), unit
        )
        if values["value_m"] is None:
            raise ValueError("Contour without depth")
        category, zoom = contour_presentation(values["value_m"])
        return [
            DepthContour(
                **fields, **values, contour_class=category, display_minzoom=zoom
            )
        ]
    if kind == "sounding":
        coords = feature["geometry"]["coordinates"]
        if geometry.geom_type == "Point":
            coords = [coords]
        elif geometry.geom_type != "MultiPoint":
            raise ValueError("Sounding must be Point or MultiPoint")
        depths = p.get("depths")
        if depths is not None and (
            not isinstance(depths, list) or len(depths) != len(coords)
        ):
            raise ValueError("Unpaired sounding depths")
        result = []
        for index, coordinate in enumerate(coords):
            # Per-vertex Z takes precedence. A scalar Z belongs only to a Point.
            value = (
                coordinate[2]
                if len(coordinate) >= 3
                else depths[index]
                if depths is not None
                else p.get("z")
                if len(coords) == 1
                else None
            )
            if geometry.geom_type == "Point" and p.get("z") is not None:
                # ArcGIS XYZ can carry floating point transport noise while
                # the published Z attribute is exact (e.g. 0.9 vs 0.89999...).
                if value is not None and abs(float(value) - float(p["z"])) > 1e-6:
                    raise ValueError("Contradictory point sounding depths")
                value = p["z"]
            values = depth_values(value, unit)
            if values["value_m"] is None:
                raise ValueError("Missing per-coordinate sounding depth")
            sample = {**fields, "geometry": Point(coordinate[:2])}
            if geometry.geom_type == "MultiPoint":
                sample.update(
                    id=f"{fields['id']}:{index}",
                    source_id=f"{fields['source_id']}:{index}",
                )
            result.append(Sounding(**sample, **values, sample_index=index))
        return result
    values = depth_values(
        p.get("brassiage") if source == "shom" else p.get("valsou"), unit
    )
    # Shom publishes brassiage with qualifications, not always a measured minimum.
    least = (
        values["value_m"]
        if source != "shom" or p.get("precis_bra") == "brassiage minimal connu"
        else None
    )
    level = text(p.get("watlev"))
    return [
        UnderwaterHazard(
            **fields,
            **values,
            hazard_type=kind,
            category=text(
                p.get(
                    {"wreck": "catwrk", "obstruction": "catobs", "rock": "category"}[
                        kind
                    ]
                )
                or p.get("type_obj")
            )
            or None,
            water_level=WATER_LEVEL.get(level, level) or None,
            least_depth=least,
        )
    ]


def select_soundings(features, zoom):
    """Nested global Mercator grids, not tile-relative random sampling.

    Keep the shallowest known value in each cell; accuracy breaks depth ties,
    then stable ID. Harbour/berthing charts use 64/32/32px cells at z14/15/16,
    other purposes 128/64/64px. Powers of two preserve nested boundaries. Promoted
    shallow samples stay selected at deeper zooms. No datum-equivalence merge.
    """
    from app.domain.marine_tile import project, HALF_WORLD

    assigned = {f.id: 16 for f in features}
    for z in (14, 15, 16):
        pixel_size = 2 * HALF_WORLD / (2**z * 512)
        cells = {}
        for f in features:
            x, y = project(f.geometry.x, f.geometry.y)
            local = f.scale in {"harbour", "berthing", "survey"}
            size = pixel_size * (
                (64 if z == 14 else 32) if local else (128 if z == 14 else 64)
            )
            # Unknown references from different datasets are not assumed compatible.
            reference = (
                f.vertical_datum,
                f.sounding_datum,
                None
                if f.vertical_datum
                else (
                    f.source,
                    json.loads(f.source_attributes).get("DSNM")
                    or json.loads(f.source_attributes).get("dsnm")
                    or f.source_id.rpartition(":")[0],
                ),
            )
            key = (
                local,
                reference,
                int((x + HALF_WORLD) // size),
                int((y + HALF_WORLD) // size),
            )
            order = (
                f.value_m,
                f.accuracy if f.accuracy is not None else float("inf"),
                -f.source_priority,
                f.id,
            )
            if key not in cells or order < cells[key][0]:
                cells[key] = (order, f)
        for _, f in cells.values():
            assigned[f.id] = min(assigned[f.id], z)
        if z == zoom:
            return [
                replace(f, display_minzoom=assigned[f.id])
                for _, f in sorted(cells.values(), key=lambda item: item[1].id)
            ]
    return []
