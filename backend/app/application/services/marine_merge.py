"""Conservative object matching. Ambiguity is observable and retains both objects."""

import math
import re
from dataclasses import replace

from shapely.geometry import box
from shapely.ops import transform
from shapely.strtree import STRtree

from app.domain.marine import MergeResult, SeamarkFeature
from app.domain.marine_tile import project


def _name(value):
    return re.sub(r"[^\w]", "", value.casefold())


def _point_match(a, b, ga, gb):
    distance = ga.distance(gb)
    if a.type != b.type or distance > 35:
        return False, False
    fields = (
        "category",
        "color",
        "color_pattern",
        "shape",
        "topmark_shape",
        "topmark_color",
        "navigation_system",
    )
    fields = tuple(
        f for f in fields if f not in a.inferred_fields and f not in b.inferred_fields
    )
    conflict = any(
        getattr(a, f) and getattr(b, f) and getattr(a, f) != getattr(b, f)
        for f in fields
    )
    if conflict:
        return False, distance <= 15
    same_id = bool(set(a.external_ids) & set(b.external_ids))
    same_name = bool(a.name and b.name and _name(a.name) == _name(b.name))
    if a.name and b.name and not same_name and not same_id:
        return False, distance <= 15
    equal = sum(bool(getattr(a, f)) and getattr(a, f) == getattr(b, f) for f in fields)
    # Close, semantically corroborated points OR a shared identity/name nearby.
    # A distance alone (even zero) is never enough.
    match = (
        (same_id and distance <= 35)
        or (same_name and equal >= 1 and distance <= 25)
        or (distance <= 6 and equal >= 2 and a.color)
        or (distance <= 15 and equal >= 3 and a.color)
    )
    return bool(match), not match and distance <= 15


def _line_angle(line):
    points = list(line.coords)
    return (
        math.degrees(
            math.atan2(points[-1][1] - points[0][1], points[-1][0] - points[0][0])
        )
        % 180
    )


def _port_match(a, b, ga, gb):
    if a.infrastructure_type != b.infrastructure_type:
        # Shortbread pier does not distinguish floating pontoons. Only this
        # coarse fallback category can match an official pontoon.
        if not (
            {a.infrastructure_type, b.infrastructure_type} == {"pier", "pontoon"}
            and "osm" in {a.source, b.source}
        ):
            return False, False
    if a.harbour and b.harbour and _name(a.harbour) != _name(b.harbour):
        return False, False
    if a.name and b.name and _name(a.name) != _name(b.name):
        return False, False
    if set(a.external_ids) & set(b.external_ids):
        return True, False
    polygons = {"Polygon", "MultiPolygon"}
    if ga.geom_type in polygons and gb.geom_type in polygons:
        overlap = ga.intersection(gb).area
        union = ga.union(gb).area
        return union > 0 and overlap / union >= 0.82, overlap > 0 and overlap / max(
            ga.area, gb.area
        ) < 0.82
    if ga.geom_type == gb.geom_type == "LineString":
        if not ga.length or not gb.length:
            return False, False
        angle = abs(_line_angle(ga) - _line_angle(gb))
        angle = min(angle, 180 - angle)
        ratio = min(ga.length, gb.length) / max(ga.length, gb.length)
        # Unnamed parallel adjacent piers must not collapse. Small displacement
        # plus near-identical endpoints/length/orientation are all required.
        tolerance = 3 if a.name and b.name else 1.5
        endpoints_a, endpoints_b = list(ga.coords), list(gb.coords)
        anchors = min(
            max(
                math.dist(endpoints_a[0], endpoints_b[0]),
                math.dist(endpoints_a[-1], endpoints_b[-1]),
            ),
            max(
                math.dist(endpoints_a[0], endpoints_b[-1]),
                math.dist(endpoints_a[-1], endpoints_b[0]),
            ),
        )
        corroborated = bool(a.name and b.name) or ga.intersects(gb) or anchors <= 0.75
        match = (
            ratio >= 0.85
            and angle <= 8
            and ga.hausdorff_distance(gb) <= tolerance
            and corroborated
        )
        return match, not match and ga.distance(gb) < 5 and ratio > 0.7 and angle < 15
    # A centerline lying almost entirely INSIDE a narrow polygon can represent
    # the same pier/breakwater. An adjacent quay outside it cannot match.
    line, polygon = (ga, gb) if gb.geom_type in polygons else (gb, ga)
    if line.geom_type == "LineString" and polygon.geom_type in polygons and line.length:
        rectangle = polygon.minimum_rotated_rectangle
        edges = list(rectangle.exterior.coords)
        lengths = [math.dist(edges[i], edges[i + 1]) for i in range(4)]
        length, width = max(lengths), min(lengths)
        inside = line.intersection(polygon).length / line.length
        match = (
            width <= 30
            and 0.8 <= line.length / max(length, 0.01) <= 1.2
            and inside >= 0.95
        )
        return match, not match and inside > 0.5
    # Points and heterogeneous/fragmented geometry have no safe implicit merge.
    return False, False


def merge_features(features, bounds) -> MergeResult:
    result = MergeResult()
    if not features:
        return result
    # One common local projection for both operands, never separate origins.
    latitude = (bounds[1] + bounds[3]) / 2
    factor = math.cos(math.radians(latitude))
    projection = lambda lon, lat: tuple(v * factor for v in project(lon, lat))
    ordered = sorted(
        features,
        key=lambda f: (-f.source_priority, f.source, f.source_id, f.geometry.wkb_hex),
    )
    # Keep the upstream tile buffer and match before final MVT clipping.
    geometries = [transform(projection, f.geometry) for f in ordered]
    tree = STRtree(geometries)
    absorbed = set()
    for i, feature in enumerate(ordered):
        if i in absorbed:
            continue
        provenance = set(feature.provenance)
        # Query by bbox then verify actual geometry and semantics. Stable order.
        for j in sorted(
            int(j) for j in tree.query(geometries[i].buffer(35)) if int(j) > i
        ):
            if j in absorbed:
                continue
            candidate = ordered[j]
            if type(feature) is not type(candidate):
                continue
            # Distinct objects from the same dataset are not cross-source
            # duplicates, even if colocated. Cross-scale NOAA is eligible.
            if feature.source == candidate.source and (
                feature.source != "noaa" or feature.scale == candidate.scale
            ):
                if feature.id != candidate.id:
                    continue
            matcher = (
                _point_match if isinstance(feature, SeamarkFeature) else _port_match
            )
            matched, ambiguous = matcher(
                feature, candidate, geometries[i], geometries[j]
            )
            if (
                matched
                and isinstance(feature, SeamarkFeature)
                and feature.source != candidate.source
            ):
                # A fallback equally compatible with two distinct nearby official
                # points has no unique assignment. Keep it as an ambiguity.
                distance = geometries[i].distance(geometries[j])
                for k in tree.query(geometries[j].buffer(35)):
                    k = int(k)
                    other = ordered[k]
                    if (
                        k in {i, j}
                        or k in absorbed
                        or other.source != feature.source
                        or not isinstance(other, SeamarkFeature)
                    ):
                        continue
                    if (
                        _point_match(other, candidate, geometries[k], geometries[j])[0]
                        and geometries[k].distance(geometries[j]) <= distance + 2
                    ):
                        matched, ambiguous = False, True
                        break
            if matched:
                absorbed.add(j)
                provenance.update(candidate.provenance)
                result.matches.append((feature.id, candidate.id))
            elif ambiguous:
                result.conflicts.append((feature.id, candidate.id))
        result.features.append(replace(feature, provenance=tuple(sorted(provenance))))
    return result
