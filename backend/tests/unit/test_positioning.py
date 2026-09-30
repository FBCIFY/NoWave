from datetime import UTC, datetime
from math import nan

import pytest

from app.domain.errors import (
    GpsPrecisionInsufficientError,
    InvalidPositioningInputError,
)
from app.domain.positioning import (
    ALGORITHM_VERSION,
    PositioningMeasurements,
    estimate_position,
)


def measurements(
    **changes,
):
    values = {
        "observer_longitude": 5.3779,
        "observer_latitude": 43.2945,
        "gps_accuracy_m": 12.0,
        "azimuth_deg": 0.0,
        "inclination_deg": -30.0,
        "camera_height_m": 2.0,
        "camera_height_source": (
            "device_estimate"
        ),
        "camera_height_uncertainty_m": 0.1,
        "focal_length_mm": 24.0,
        "zoom_ratio": 1.0,
        "captured_at": datetime(
            2026,
            9,
            28,
            10,
            0,
            tzinfo=UTC,
        ),
    }

    values.update(changes)

    return PositioningMeasurements(
        **values
    )


def test_known_reference_true_north():
    result = estimate_position(
        measurements()
    )

    assert result.available is True

    assert (
        result.algorithm_version
        == ALGORITHM_VERSION
    )

    assert result.distance_m == pytest.approx(
        4.0,
        abs=0.01,
    )

    assert result.longitude == pytest.approx(
        5.3779,
        abs=0.000001,
    )

    assert result.latitude > 43.2945


def test_known_reference_true_east():
    result = estimate_position(
        measurements(
            azimuth_deg=90.0,
        )
    )

    assert result.available is True

    assert result.distance_m == pytest.approx(
        4.0,
        abs=0.01,
    )

    assert result.longitude > 5.3779

    assert result.latitude == pytest.approx(
        43.2945,
        abs=0.000001,
    )


def test_horizon_returns_unavailable():
    result = estimate_position(
        measurements(
            inclination_deg=0.0,
        )
    )

    assert result.available is False
    assert result.longitude is None
    assert result.latitude is None
    assert result.distance_m is None


def test_upward_view_returns_unavailable():
    result = estimate_position(
        measurements(
            inclination_deg=10.0,
        )
    )

    assert result.available is False


def test_near_horizon_without_intersection():
    result = estimate_position(
        measurements(
            inclination_deg=-0.01,
        )
    )

    assert result.available is False


def test_near_horizon_with_intersection():
    result = estimate_position(
        measurements(
            inclination_deg=-0.05,
        )
    )

    assert result.available is True

    assert 3000 < result.distance_m < 3500


def test_exactly_50_meters_accuracy_is_accepted():
    result = estimate_position(
        measurements(
            gps_accuracy_m=50.0,
        )
    )

    assert result.available is True


def test_accuracy_above_50_raises_specific_error():
    with pytest.raises(
        GpsPrecisionInsufficientError
    ):
        measurements(
            gps_accuracy_m=50.1,
        )


def test_nan_is_rejected():
    with pytest.raises(
        InvalidPositioningInputError
    ):
        measurements(
            inclination_deg=nan,
        )


def test_negative_height_is_rejected():
    with pytest.raises(
        InvalidPositioningInputError
    ):
        measurements(
            camera_height_m=-1.0,
        )


def test_negative_height_uncertainty_is_rejected():
    with pytest.raises(
        InvalidPositioningInputError
    ):
        measurements(
            camera_height_uncertainty_m=-0.1,
        )


def test_zero_focal_length_is_rejected():
    with pytest.raises(
        InvalidPositioningInputError
    ):
        measurements(
            focal_length_mm=0.0,
        )


def test_zero_zoom_is_rejected():
    with pytest.raises(
        InvalidPositioningInputError
    ):
        measurements(
            zoom_ratio=0.0,
        )


def test_naive_capture_time_is_rejected():
    with pytest.raises(
        InvalidPositioningInputError
    ):
        measurements(
            captured_at=datetime(
                2026,
                9,
                28,
                10,
                0,
            ),
        )


def test_extremely_large_height_is_rejected():
    with pytest.raises(
        InvalidPositioningInputError
    ):
        measurements(
            camera_height_m=1e100,
        )
