from datetime import UTC, datetime, timedelta
from uuid import uuid4

import psycopg
import pytest

from app.domain.positioning import (
    PositioningMeasurements,
    estimate_position,
)
from app.domain.report import (
    Report,
    ReportCategory,
    ReportPositioningMode,
)
from app.domain.report_photo import UploadStatus
from app.domain.user import User
from app.infrastructure.repositories.postgresql_report_repository import (
    PostgreSQLReportRepository,
)
from app.infrastructure.repositories.postgresql_user_repository import (
    PostgreSQLUserRepository,
)


def create_user():
    return User(
        firebase_uid=f"firebase-photo-{uuid4()}",
        username=f"photo-{uuid4()}",
        email=f"{uuid4()}@nowave.test",
    )


def create_measurements(captured_at):
    return PositioningMeasurements(
        observer_longitude=5.3779,
        observer_latitude=43.2945,
        gps_accuracy_m=12.0,
        azimuth_deg=145.2,
        inclination_deg=-30.0,
        camera_height_m=2.1,
        camera_height_source="device_estimate",
        camera_height_uncertainty_m=0.1,
        focal_length_mm=24.0,
        zoom_ratio=1.0,
        captured_at=captured_at,
    )


def test_save_photo_creates_three_rows(
    dsn,
    monkeypatch,
):
    monkeypatch.setenv(
        "DATABASE_URL",
        dsn,
    )

    user_repository = PostgreSQLUserRepository()
    report_repository = PostgreSQLReportRepository()

    user = create_user()
    user_repository.save(user)

    observed_at = (
        datetime.now(UTC)
        - timedelta(minutes=5)
    )

    report = Report.create_photo(
        author_id=user.id,
        client_report_id=uuid4(),
        category=ReportCategory.POLLUTION,
        longitude=5.40,
        latitude=43.31,
        observed_at=observed_at,
        description="Pollution visible",
    )

    measurements = create_measurements(
        captured_at=observed_at,
    )

    estimate = estimate_position(
        measurements
    )

    saved_report = report_repository.save_photo(
        report=report,
        measurements=measurements,
        estimate=estimate,
    )

    assert saved_report is not None
    assert saved_report.id == report.id

    assert (
        saved_report.positioning_mode
        == ReportPositioningMode.PHOTO
    )

    # final_position reste la position
    # confirmée par l'utilisateur
    assert saved_report.longitude == pytest.approx(
        5.40
    )

    assert saved_report.latitude == pytest.approx(
        43.31
    )

    stored_positioning = (
        report_repository.get_photo_positioning(
            report.id
        )
    )

    assert stored_positioning is not None

    assert (
        stored_positioning.measurements
        == measurements
    )

    assert (
        stored_positioning.estimated_longitude
        == pytest.approx(
            estimate.longitude
        )
    )

    assert (
        stored_positioning.estimated_latitude
        == pytest.approx(
            estimate.latitude
        )
    )

    assert (
        stored_positioning.estimated_distance_m
        == pytest.approx(
            estimate.distance_m
        )
    )

    assert (
        report_repository.get_photo_status(
            report.id
        )
        == UploadStatus.PENDING
    )

    with psycopg.connect(dsn) as connection:
        report_count = connection.execute(
            """
            SELECT COUNT(*)
            FROM nowave.reports
            WHERE id = %s
            """,
            (report.id,),
        ).fetchone()[0]

        positioning_count = connection.execute(
            """
            SELECT COUNT(*)
            FROM nowave.report_positioning
            WHERE report_id = %s
            """,
            (report.id,),
        ).fetchone()[0]

        photo_count = connection.execute(
            """
            SELECT COUNT(*)
            FROM nowave.report_photos
            WHERE report_id = %s
            """,
            (report.id,),
        ).fetchone()[0]

    assert report_count == 1
    assert positioning_count == 1
    assert photo_count == 1


def test_save_photo_rolls_back_everything_on_failure(
    dsn,
    monkeypatch,
):
    monkeypatch.setenv(
        "DATABASE_URL",
        dsn,
    )

    user_repository = PostgreSQLUserRepository()
    report_repository = PostgreSQLReportRepository()

    user = create_user()
    user_repository.save(user)

    observed_at = (
        datetime.now(UTC)
        - timedelta(minutes=5)
    )

    report = Report.create_photo(
        author_id=user.id,
        client_report_id=uuid4(),
        category=ReportCategory.OBSTRUCTION,
        longitude=5.40,
        latitude=43.31,
        observed_at=observed_at,
    )

    measurements = create_measurements(
        captured_at=observed_at,
    )

    estimate = estimate_position(
        measurements
    )

    def fail_photo_insert(
        cursor,
        report,
    ):
        raise RuntimeError(
            "simulated photo metadata failure"
        )

    monkeypatch.setattr(
        report_repository,
        "_insert_pending_photo",
        fail_photo_insert,
    )

    with pytest.raises(
        RuntimeError,
        match="simulated photo metadata failure",
    ):
        report_repository.save_photo(
            report=report,
            measurements=measurements,
            estimate=estimate,
        )

    with psycopg.connect(dsn) as connection:
        report_count = connection.execute(
            """
            SELECT COUNT(*)
            FROM nowave.reports
            WHERE id = %s
            """,
            (report.id,),
        ).fetchone()[0]

        positioning_count = connection.execute(
            """
            SELECT COUNT(*)
            FROM nowave.report_positioning
            WHERE report_id = %s
            """,
            (report.id,),
        ).fetchone()[0]

        photo_count = connection.execute(
            """
            SELECT COUNT(*)
            FROM nowave.report_photos
            WHERE report_id = %s
            """,
            (report.id,),
        ).fetchone()[0]

    assert report_count == 0
    assert positioning_count == 0
    assert photo_count == 0


def test_photo_without_estimate_is_persisted(
    dsn,
    monkeypatch,
):
    monkeypatch.setenv(
        "DATABASE_URL",
        dsn,
    )

    user_repository = PostgreSQLUserRepository()
    report_repository = PostgreSQLReportRepository()

    user = create_user()
    user_repository.save(user)

    observed_at = (
        datetime.now(UTC)
        - timedelta(minutes=5)
    )

    report = Report.create_photo(
        author_id=user.id,
        client_report_id=uuid4(),
        category=ReportCategory.OBSTRUCTION,
        longitude=5.40,
        latitude=43.31,
        observed_at=observed_at,
    )

    measurements = PositioningMeasurements(
        observer_longitude=5.3779,
        observer_latitude=43.2945,
        gps_accuracy_m=12.0,
        azimuth_deg=145.2,
        inclination_deg=0.0,
        camera_height_m=2.1,
        captured_at=observed_at,
    )

    estimate = estimate_position(
        measurements
    )

    assert estimate.available is False

    saved_report = report_repository.save_photo(
        report=report,
        measurements=measurements,
        estimate=estimate,
    )

    assert saved_report is not None

    stored = (
        report_repository.get_photo_positioning(
            report.id
        )
    )

    assert stored is not None
    assert stored.estimated_longitude is None
    assert stored.estimated_latitude is None
    assert stored.estimated_distance_m is None

    assert (
        report_repository.get_photo_status(
            report.id
        )
        == UploadStatus.PENDING
    )
