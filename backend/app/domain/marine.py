"""Marine data contracts. Coordinates are always WGS84 longitude, latitude.

These display features are not official navigational products. Providers retain
source geometry and semantics; presentation mappings belong to the tile encoder.
"""

from dataclasses import dataclass, field
from enum import StrEnum
from typing import Literal

from shapely.geometry.base import BaseGeometry


class MarineFamily(StrEnum):
    SEAMARKS = "seamarks"
    PORTS = "port-infrastructure"


class ProviderUnavailable(RuntimeError):
    """A provider cannot produce a trustworthy result for this request."""


BUOY_TYPES = frozenset(
    {
        "buoy_lateral",
        "buoy_cardinal",
        "buoy_isolated_danger",
        "buoy_safe_water",
        "buoy_special_purpose",
    }
)


@dataclass(frozen=True, kw_only=True)
class MarineFeature:
    id: str
    geometry: BaseGeometry
    source: str
    source_id: str
    source_priority: int
    source_updated_at: str = ""  # A real revision date, never fetch time.
    source_date: str = ""  # S-57 SORDAT is the source date, not revision time.
    provenance: tuple[str, ...] = ()
    name: str = ""
    scale: str = ""
    scamin: int | None = None
    external_ids: tuple[str, ...] = ()

    def __post_init__(self):
        if not self.id or not self.source or not self.source_id:
            raise ValueError("Marine features need source identifiers")
        if self.geometry.is_empty or not self.geometry.is_valid:
            raise ValueError("Marine features need valid, nonempty geometry")
        west, south, east, north = self.geometry.bounds
        if not (-180 <= west <= east <= 180 and -90 <= south <= north <= 90):
            raise ValueError("Marine geometry must be longitude/latitude")


@dataclass(frozen=True, kw_only=True)
class SeamarkFeature(MarineFeature):
    type: str
    category: str = ""
    color: str = ""
    color_pattern: str = ""
    shape: str = ""
    topmark_shape: str = ""
    topmark_color: str = ""
    navigation_system: Literal["IALA_A", "IALA_B", ""] = ""
    inferred_fields: tuple[str, ...] = ()

    def __post_init__(self):
        super().__post_init__()
        if self.geometry.geom_type != "Point":
            raise ValueError("Current seamarks must be points")


PortType = Literal[
    "dock",
    "pier",
    "breakwater",
    "groyne",
    "quay",
    "mole",
    "pontoon",
    "harbour",
    "basin",
    "jetty",
    "shoreline_construction",
]


@dataclass(frozen=True, kw_only=True)
class PortInfrastructureFeature(MarineFeature):
    infrastructure_type: PortType
    harbour: str = ""
    # Preserve source category, including unstyled construction types.
    source_category: str = ""

    def __post_init__(self):
        super().__post_init__()
        if self.geometry.geom_type not in {
            "Point",
            "LineString",
            "MultiLineString",
            "Polygon",
            "MultiPolygon",
        }:
            raise ValueError("Unsupported infrastructure geometry")


Feature = SeamarkFeature | PortInfrastructureFeature


@dataclass(frozen=True)
class ProviderBatch:
    features: tuple[Feature, ...] = ()
    failures: tuple[str, ...] = ()


@dataclass
class MergeResult:
    features: list[Feature] = field(default_factory=list)
    matches: list[tuple[str, str]] = field(default_factory=list)
    conflicts: list[tuple[str, str]] = field(default_factory=list)
