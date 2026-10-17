"""S-57 Edition 3.1 attributes, not the different S-101 enumerations."""

import re
from dataclasses import replace

from shapely.geometry import shape

from app.domain.marine import PortInfrastructureFeature, SeamarkFeature

COLORS = {
    1: "white",
    2: "black",
    3: "red",
    4: "green",
    5: "blue",
    6: "yellow",
    7: "grey",
    8: "brown",
    9: "amber",
    10: "violet",
    11: "orange",
    12: "magenta",
    13: "pink",
}
PATTERNS = {
    1: "horizontal",
    2: "vertical",
    3: "diagonal",
    4: "squared",
    5: "stripes",
    6: "border",
}
LATERAL = {
    1: "port",
    2: "starboard",
    3: "preferred_channel_starboard",
    4: "preferred_channel_port",
}
CARDINAL = {1: "north", 2: "east", 3: "south", 4: "west"}
SHAPES = {
    1: "conical",
    2: "can",
    3: "spherical",
    4: "pillar",
    5: "spar",
    6: "barrel",
    7: "super_buoy",
    8: "ice_buoy",
}
TOPMARKS = {
    1: "cone_up",
    2: "cone_down",
    3: "sphere",
    4: "2_spheres",
    5: "cylinder",
    6: "board",
    7: "x_shape",
    8: "cross",
    9: "cube_point_up",
    10: "2_cones_point_together",
    11: "2_cones_base_together",
    12: "rhombus",
    13: "2_cones_up",
    14: "2_cones_down",
}
CONSTRUCTIONS = {
    1: "breakwater",
    2: "groyne",
    3: "mole",
    4: "pier",
    5: "pier",
    6: "quay",
}
CLASSES = {
    "boycar": "buoy_cardinal",
    "boyisd": "buoy_isolated_danger",
    "boylat": "buoy_lateral",
    "boysaw": "buoy_safe_water",
    "boyspp": "buoy_special_purpose",
}


def text(value):
    return "" if value is None else str(value).strip()


def codes(value, table):
    result = []
    for part in re.split(r"[,;]", text(value)):
        if not part:
            continue
        try:
            result.append(table.get(int(part), f"unknown_{part}"))
        except ValueError:
            result.append(part.lower().replace(" ", "_"))
    return "_".join(result)


def integer(value):
    try:
        return int(float(value))
    except (TypeError, ValueError):
        return None


def attributes(feature):
    return {k.lower(): v for k, v in feature["properties"].items()}


def source_fields(feature, *, source, dataset, priority, scale=""):
    p = attributes(feature)
    sid = text(p.get("inspireid")) or text(feature.get("id"))
    if not sid:
        raise ValueError("Missing stable upstream feature identifier")
    source_id = f"{dataset}:{sid}"
    return dict(
        id=f"{source}:{source_id}",
        geometry=shape(feature["geometry"]),
        source=source,
        source_id=source_id,
        source_priority=priority,
        name=text(p.get("objnam")),
        provenance=(f"{source}:{source_id}",),
        scale=scale,
        scamin=integer(p.get("scamin")),
        source_date=text(p.get("sordat")),
        external_ids=tuple(f"{k}:{p[k]}" for k in ("inspireid", "numald") if p.get(k)),
    )


def seamark(feature, feature_type, *, source, dataset, priority, scale=""):
    p = attributes(feature)
    system = {1: "IALA_A", 2: "IALA_B"}.get(integer(p.get("marsys")), "")
    # NOAA ENCs cover US waters, an IALA B authority. SHOM does not publish
    # MARSYS here: only documented French Caribbean/Guiana/SPM are region B.
    if not system and source == "noaa":
        system = "IALA_B"
    if not system and source == "shom":
        lon, lat = feature["geometry"]["coordinates"]
        system = "IALA_B" if (-65 <= lon <= -50 and 0 <= lat <= 52) else "IALA_A"
    return SeamarkFeature(
        **source_fields(
            feature, source=source, dataset=dataset, priority=priority, scale=scale
        ),
        type=feature_type,
        category=codes(p.get("catcam"), CARDINAL)
        if feature_type == "buoy_cardinal"
        else codes(p.get("catlam"), LATERAL)
        if feature_type == "buoy_lateral"
        else text(p.get("catspm")),
        color=codes(p.get("colour"), COLORS),
        color_pattern=codes(p.get("colpat"), PATTERNS),
        shape=codes(p.get("boyshp"), SHAPES),
        navigation_system=system,
    )


def attach_topmark(buoy, topmark):
    p = attributes(topmark)
    top_id = text(p.get("inspireid")) or text(topmark.get("id"))
    return replace(
        buoy,
        topmark_shape=codes(p.get("topshp"), TOPMARKS),
        topmark_color=codes(p.get("colour"), COLORS),
        provenance=(*buoy.provenance, f"{buoy.source}:topmark:{top_id}"),
    )


def infrastructure(feature, object_class, *, source, dataset, priority, scale=""):
    p = attributes(feature)
    category = text(p.get("catslc"))
    kind = "dock" if object_class == "dock" else CONSTRUCTIONS.get(integer(category))
    # ENC Direct sometimes returns human readable domain values.
    if not kind:
        kind = {
            "breakwater": "breakwater",
            "groin": "groyne",
            "groyne (groin)": "groyne",
            "mole": "mole",
            "pier": "pier",
            "pier (jetty)": "pier",
            "promenade pier": "pier",
            "wharf": "quay",
            "wharf (quay)": "quay",
        }.get(category.lower(), "shoreline_construction")
    return PortInfrastructureFeature(
        **source_fields(
            feature, source=source, dataset=dataset, priority=priority, scale=scale
        ),
        infrastructure_type=kind,
        source_category=category,
    )
