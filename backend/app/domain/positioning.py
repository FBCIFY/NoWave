from dataclasses import dataclass
from datetime import UTC, datetime
from math import (
    asin,
    atan2,
    cos,
    degrees,
    isfinite,
    radians,
    sin,
    sqrt,
)

from app.domain.errors import (
    GpsPrecisionInsufficientError,
    InvalidPositioningInputError,
)


EARTH_RADIUS_M = 6_371_008.8
ALGORITHM_VERSION = "centered_ray_sphere_v1"


@dataclass(frozen=True)
class PositioningMeasurements:
    observer_longitude: float
    observer_latitude: float
    gps_accuracy_m: float
    azimuth_deg: float
    inclination_deg: float
    camera_height_m: float
    captured_at: datetime

    camera_height_source: str | None = None
    camera_height_uncertainty_m: float | None = None
    focal_length_mm: float | None = None
    zoom_ratio: float | None = None

    def __post_init__(self) -> None:
        required_values = {
            "observer_longitude": self.observer_longitude,
            "observer_latitude": self.observer_latitude,
            "gps_accuracy_m": self.gps_accuracy_m,
            "azimuth_deg": self.azimuth_deg,
            "inclination_deg": self.inclination_deg,
            "camera_height_m": self.camera_height_m,
        }

        for name, value in required_values.items():
            if not isfinite(value):
                raise InvalidPositioningInputError(
                    f"{name} must be finite"
                )

        if not -180 <= self.observer_longitude <= 180:
            raise InvalidPositioningInputError(
                "observer longitude must be between -180 and 180"
            )

        if not -90 <= self.observer_latitude <= 90:
            raise InvalidPositioningInputError(
                "observer latitude must be between -90 and 90"
            )

        if self.gps_accuracy_m < 0:
            raise InvalidPositioningInputError(
                "gps_accuracy_m must be greater than or equal to 0"
            )

        if self.gps_accuracy_m > 50:
            raise GpsPrecisionInsufficientError(
                self.gps_accuracy_m
            )

        if not 0 <= self.azimuth_deg < 360:
            raise InvalidPositioningInputError(
                "azimuth_deg must be between 0 inclusive and 360 exclusive"
            )

        if self.camera_height_m <= 0:
            raise InvalidPositioningInputError(
                "camera_height_m must be greater than 0"
            )

        if (
            self.camera_height_source is not None
            and len(self.camera_height_source) > 30
        ):
            raise InvalidPositioningInputError(
                "camera_height_source cannot exceed 30 characters"
            )

        optional_values = {
            "camera_height_uncertainty_m": (
                self.camera_height_uncertainty_m
            ),
            "focal_length_mm": self.focal_length_mm,
            "zoom_ratio": self.zoom_ratio,
        }

        for name, value in optional_values.items():
            if value is None:
                continue

            if not isfinite(value):
                raise InvalidPositioningInputError(
                    f"{name} must be finite"
                )

        if (
            self.camera_height_uncertainty_m is not None
            and self.camera_height_uncertainty_m < 0
        ):
            raise InvalidPositioningInputError(
                "camera_height_uncertainty_m must be greater than or equal to 0"
            )

        if (
            self.focal_length_mm is not None
            and self.focal_length_mm <= 0
        ):
            raise InvalidPositioningInputError(
                "focal_length_mm must be greater than 0"
            )

        if (
            self.zoom_ratio is not None
            and self.zoom_ratio <= 0
        ):
            raise InvalidPositioningInputError(
                "zoom_ratio must be greater than 0"
            )

        if (
            self.captured_at.tzinfo is None
            or self.captured_at.utcoffset() is None
        ):
            raise InvalidPositioningInputError(
                "captured_at must include a timezone"
            )

        object.__setattr__(
            self,
            "captured_at",
            self.captured_at.astimezone(UTC),
        )


@dataclass(frozen=True)
class PositionEstimateResult:
    longitude: float | None
    latitude: float | None
    distance_m: float | None
    algorithm_version: str = ALGORITHM_VERSION

    @property
    def available(self) -> bool:
        return (
            self.longitude is not None
            and self.latitude is not None
            and self.distance_m is not None
        )


def estimate_position(
    measurements: PositioningMeasurements,
) -> PositionEstimateResult:
    inclination_deg = measurements.inclination_deg

    if inclination_deg >= 0 or inclination_deg < -90:
        return _unavailable_estimate()

    inclination_rad = radians(inclination_deg)

    observer_radius = (
        EARTH_RADIUS_M
        + measurements.camera_height_m
    )

    radial_projection = (
        observer_radius
        * sin(inclination_rad)
    )

    altitude_term = (
        2
        * EARTH_RADIUS_M
        * measurements.camera_height_m
        + measurements.camera_height_m**2
    )

    discriminant = (
        radial_projection**2
        - altitude_term
    )

    if discriminant < 0:
        return _unavailable_estimate()

    denominator = (
        -radial_projection
        + sqrt(discriminant)
    )

    if denominator <= 0:
        return _unavailable_estimate()

    ray_distance_m = (
        altitude_term
        / denominator
    )

    tangent_component = (
        ray_distance_m
        * cos(inclination_rad)
    )

    radial_component = (
        observer_radius
        + ray_distance_m
        * sin(inclination_rad)
    )

    central_angle = atan2(
        tangent_component,
        radial_component,
    )

    if central_angle < 0:
        return _unavailable_estimate()

    longitude, latitude = _destination_point(
        observer_longitude=measurements.observer_longitude,
        observer_latitude=measurements.observer_latitude,
        azimuth_deg=measurements.azimuth_deg,
        central_angle=central_angle,
    )

    return PositionEstimateResult(
        longitude=longitude,
        latitude=latitude,
        distance_m=ray_distance_m,
    )


def _unavailable_estimate() -> PositionEstimateResult:
    return PositionEstimateResult(
        longitude=None,
        latitude=None,
        distance_m=None,
    )


def _destination_point(
    observer_longitude: float,
    observer_latitude: float,
    azimuth_deg: float,
    central_angle: float,
) -> tuple[float, float]:
    latitude_rad = radians(observer_latitude)
    longitude_rad = radians(observer_longitude)
    azimuth_rad = radians(azimuth_deg)

    sin_target_latitude = (
        sin(latitude_rad)
        * cos(central_angle)
        + cos(latitude_rad)
        * sin(central_angle)
        * cos(azimuth_rad)
    )

    sin_target_latitude = max(
        -1.0,
        min(
            1.0,
            sin_target_latitude,
        ),
    )

    target_latitude_rad = asin(
        sin_target_latitude
    )

    longitude_delta = atan2(
        sin(azimuth_rad)
        * sin(central_angle)
        * cos(latitude_rad),
        cos(central_angle)
        - sin(latitude_rad)
        * sin(target_latitude_rad),
    )

    target_longitude = (
        degrees(
            longitude_rad
            + longitude_delta
        )
        + 180
    ) % 360 - 180

    target_latitude = degrees(
        target_latitude_rad
    )

    return (
        target_longitude,
        target_latitude,
    )
