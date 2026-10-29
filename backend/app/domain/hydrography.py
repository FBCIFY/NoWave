"""Depth is positive downwards; negative values are drying heights.

Unknown references/accuracy remain None. Published categories are not inferred
from depth. Source attributes retain heights separately from soundings.
"""

import math
from dataclasses import dataclass
from typing import Literal

from app.domain.marine import MarineFeature


@dataclass(frozen=True, kw_only=True)
class HydroFeature(MarineFeature):
    value_original: float | None = None
    unit_original: str | None = None
    value_m: float | None = None
    vertical_datum: str | None = None
    sounding_datum: str | None = None
    datum_reference: str | None = None
    quality: str | None = None
    accuracy: float | None = None  # published vertical uncertainty in metres
    horizontal_accuracy: float | None = None
    source_attributes: str = "{}"  # lossless JSON; MVT supports scalar properties
    source_geometry_type: str = ""
    derivation: str = "official_enc"
    license: str = "CC0-1.0"

    def __post_init__(self):
        super().__post_init__()
        for value in (
            self.value_original,
            self.value_m,
            self.accuracy,
            self.horizontal_accuracy,
        ):
            if value is not None and not math.isfinite(value):
                raise ValueError("Non-finite hydrographic value")


@dataclass(frozen=True, kw_only=True)
class DepthContour(HydroFeature):
    contour_class: Literal["major", "minor"] = "minor"
    display_minzoom: int = 12

    def __post_init__(self):
        super().__post_init__()
        if (
            self.geometry.geom_type not in {"LineString", "MultiLineString"}
            or self.value_m is None
        ):
            raise ValueError("A contour needs a line and a published depth")


@dataclass(frozen=True, kw_only=True)
class Sounding(HydroFeature):
    # MultiPoint is normalized to individual samples, each retaining its index.
    sample_index: int = 0
    nature: str = "point_sounding"
    display_minzoom: int = 16

    def __post_init__(self):
        super().__post_init__()
        if self.geometry.geom_type != "Point" or self.value_m is None:
            raise ValueError("A sounding needs one coordinate/depth pair")


@dataclass(frozen=True, kw_only=True)
class ModeledDepthCell(Sounding):
    """An existing DTM cell, never an original point observation."""

    dataset: str = "bathymetry_dtm_2024"
    year: int = 2024
    nature: str = "modeled_grid_cell"
    grid_lat_index: int
    grid_lon_index: int
    interpolation_flag: int | None = None
    value_count: int | None = None
    cdi_index: int | None = None
    display_minzoom: int = 12


@dataclass(frozen=True, kw_only=True)
class UnderwaterHazard(HydroFeature):
    hazard_type: Literal["rock", "wreck", "obstruction"]
    category: str | None = None
    water_level: str | None = None
    least_depth: float | None = None

    def __post_init__(self):
        super().__post_init__()
        if self.hazard_type not in {"rock", "wreck", "obstruction"}:
            raise ValueError("Unknown underwater hazard family")
        if self.geometry.geom_type not in {
            "Point",
            "MultiPoint",
            "LineString",
            "MultiLineString",
            "Polygon",
            "MultiPolygon",
        }:
            raise ValueError("Unsupported hazard geometry")
