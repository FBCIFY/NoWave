from datetime import UTC, datetime, timedelta
from uuid import uuid4

import pytest

from app.application.services.create_report import CreateReport
from app.domain.errors import (
    InvalidPositioningInputError,
    ReportClientIdConflictError,
)
from app.domain.positioning import PositioningMeasurements
from app.domain.report import (
    ReportCategory,
    ReportPositioningMode,
)
from app.domain.report_photo import UploadStatus
from app.domain.report_positioning import StoredReportPositioning
from app.domain.user import User


class FakeUserRepository:
    def __init__(self, user):
        self.user = user

    def get_by_firebase_uid(self, firebase_uid):
        if self.user.firebase_uid == firebase_uid:
            return self.user

        return None


class FakeReportRepository:
    def __init__(self):
        self.reports = []
        self.positioning = {}
        self.photo_status = {}

    def get_by_client_report_id(
        self,
        author_id,
        client_report_id,
    ):
        for report in self.reports:
            if (
                report.author_id == author_id
                and report.client_report_id == client_report_id
            ):
                return report

        return None

    def save(self, report):
        self.reports.append(report)
        return report

    def save_photo(
        self,
        report,
        measurements,
        estimate,
    ):
        self.reports.append(report)

        self.positioning[report.id] = StoredReportPositioning(
            report_id=report.id,
            measurements=measurements,
            estimated_longitude=estimate.longitude,
            estimated_latitude=estimate.latitude,
            estimated_distance_m=estimate.distance_m,
            algorithm_version=estimate.algorithm_version,
        )

        self.photo_status[report.id] = UploadStatus.PENDING

        return report

    def get_photo_positioning(
        self,
        report_id,
    ):
        return self.positioning.get(report_id)

    def get_photo_status(
        self,
        report_id,
    ):
        return self.photo_status.get(report_id)


def create_user():
    return User(
        firebase_uid="firebase-photo-user",
        username="photo-user",
        email="photo-user@nowave.test",
    )


def create_measurements(
    captured_at,
    inclination_deg=-30.0,
):
    return PositioningMeasurements(
        observer_longitude=5.3779,
        observer_latitude=43.2945,
        gps_accuracy_m=12.0,
        azimuth_deg=145.2,
        inclination_deg=inclination_deg,
        camera_height_m=2.1,
        camera_height_source="device_estimate",
        camera_height_uncertainty_m=0.1,
        focal_length_mm=24.0,
        zoom_ratio=1.0,
        captured_at=captured_at,
    )


def test_create_photo_report_success():
    user = create_user()
    repository = FakeReportRepository()

    service = CreateReport(
        user_repository=FakeUserRepository(user),
        report_repository=repository,
    )

    observed_at = (
        datetime.now(UTC)
        - timedelta(minutes=5)
    )

    measurements = create_measurements(
        captured_at=observed_at,
    )

    result = service.execute(
        firebase_uid=user.firebase_uid,
        client_report_id=uuid4(),
        category=ReportCategory.POLLUTION,
        longitude=5.40,
        latitude=43.31,
        observed_at=observed_at,
        description="Pollution visible",
        positioning_mode=ReportPositioningMode.PHOTO,
        positioning=measurements,
    )

    assert result.created is True

    assert (
        result.report.positioning_mode
        == ReportPositioningMode.PHOTO
    )

    # final_position reste la position choisie
    # par l'utilisateur.
    assert result.report.longitude == 5.40
    assert result.report.latitude == 43.31

    assert len(repository.reports) == 1

    assert (
        repository.get_photo_status(
            result.report.id
        )
        == UploadStatus.PENDING
    )

    stored = repository.get_photo_positioning(
        result.report.id
    )

    assert stored is not None
    assert stored.measurements == measurements


def test_identical_photo_retry_returns_existing_report():
    user = create_user()
    repository = FakeReportRepository()

    service = CreateReport(
        user_repository=FakeUserRepository(user),
        report_repository=repository,
    )

    client_report_id = uuid4()

    observed_at = (
        datetime.now(UTC)
        - timedelta(minutes=5)
    )

    measurements = create_measurements(
        captured_at=observed_at,
    )

    first = service.execute(
        firebase_uid=user.firebase_uid,
        client_report_id=client_report_id,
        category=ReportCategory.POLLUTION,
        longitude=5.40,
        latitude=43.31,
        observed_at=observed_at,
        description="Pollution visible",
        positioning_mode=ReportPositioningMode.PHOTO,
        positioning=measurements,
    )

    second = service.execute(
        firebase_uid=user.firebase_uid,
        client_report_id=client_report_id,
        category=ReportCategory.POLLUTION,
        longitude=5.40,
        latitude=43.31,
        observed_at=observed_at,
        description="Pollution visible",
        positioning_mode=ReportPositioningMode.PHOTO,
        positioning=measurements,
    )

    assert first.created is True
    assert second.created is False

    assert second.report.id == first.report.id
    assert len(repository.reports) == 1


def test_photo_retry_with_different_data_raises_conflict():
    user = create_user()
    repository = FakeReportRepository()

    service = CreateReport(
        user_repository=FakeUserRepository(user),
        report_repository=repository,
    )

    client_report_id = uuid4()

    observed_at = (
        datetime.now(UTC)
        - timedelta(minutes=5)
    )

    measurements = create_measurements(
        captured_at=observed_at,
    )

    service.execute(
        firebase_uid=user.firebase_uid,
        client_report_id=client_report_id,
        category=ReportCategory.POLLUTION,
        longitude=5.40,
        latitude=43.31,
        observed_at=observed_at,
        positioning_mode=ReportPositioningMode.PHOTO,
        positioning=measurements,
    )

    with pytest.raises(
        ReportClientIdConflictError
    ):
        service.execute(
            firebase_uid=user.firebase_uid,
            client_report_id=client_report_id,
            category=ReportCategory.OBSTRUCTION,
            longitude=5.40,
            latitude=43.31,
            observed_at=observed_at,
            positioning_mode=ReportPositioningMode.PHOTO,
            positioning=measurements,
        )

    assert len(repository.reports) == 1


def test_photo_report_can_be_created_without_estimate():
    user = create_user()
    repository = FakeReportRepository()

    service = CreateReport(
        user_repository=FakeUserRepository(user),
        report_repository=repository,
    )

    observed_at = (
        datetime.now(UTC)
        - timedelta(minutes=5)
    )

    measurements = create_measurements(
        captured_at=observed_at,
        inclination_deg=0.0,
    )

    result = service.execute(
        firebase_uid=user.firebase_uid,
        client_report_id=uuid4(),
        category=ReportCategory.OBSTRUCTION,
        longitude=5.40,
        latitude=43.31,
        observed_at=observed_at,
        positioning_mode=ReportPositioningMode.PHOTO,
        positioning=measurements,
    )

    stored = repository.get_photo_positioning(
        result.report.id
    )

    assert result.created is True
    assert stored is not None

    assert stored.estimated_longitude is None
    assert stored.estimated_latitude is None
    assert stored.estimated_distance_m is None


def test_photo_mode_requires_positioning():
    user = create_user()

    service = CreateReport(
        user_repository=FakeUserRepository(user),
        report_repository=FakeReportRepository(),
    )

    with pytest.raises(
        InvalidPositioningInputError
    ):
        service.execute(
            firebase_uid=user.firebase_uid,
            client_report_id=uuid4(),
            category=ReportCategory.POLLUTION,
            longitude=5.40,
            latitude=43.31,
            observed_at=(
                datetime.now(UTC)
                - timedelta(minutes=5)
            ),
            positioning_mode=ReportPositioningMode.PHOTO,
            positioning=None,
        )
