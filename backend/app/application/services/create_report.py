from dataclasses import dataclass
from datetime import datetime
from uuid import UUID

from app.application.ports.report_repository import ReportRepository
from app.application.ports.user_repository import UserRepository
from app.domain.errors import (
    InactiveUserError,
    InvalidPositioningInputError,
    ReportClientIdConflictError,
    UserNotFoundError,
)
from app.domain.positioning import (
    PositioningMeasurements,
    estimate_position,
)
from app.domain.report import (
    Report,
    ReportCategory,
    ReportPositioningMode,
)
from app.domain.user import UserStatus


@dataclass
class CreateReportResult:
    report: Report
    created: bool


class CreateReport:
    def __init__(
        self,
        user_repository: UserRepository,
        report_repository: ReportRepository,
    ):
        self.user_repository = user_repository
        self.report_repository = report_repository

    def execute(
        self,
        firebase_uid: str,
        client_report_id: UUID,
        category: ReportCategory,
        longitude: float,
        latitude: float,
        observed_at: datetime,
        description: str | None = None,
        positioning_mode: ReportPositioningMode = (
            ReportPositioningMode.MANUAL
        ),
        positioning: PositioningMeasurements | None = None,
    ) -> CreateReportResult:
        user = self.user_repository.get_by_firebase_uid(
            firebase_uid
        )

        if user is None:
            raise UserNotFoundError(
                "BlueWay user not found"
            )

        if user.status != UserStatus.ACTIVE:
            raise InactiveUserError(
                "user is not active"
            )

        positioning_mode = ReportPositioningMode(
            positioning_mode
        )

        self._validate_mode(
            positioning_mode=positioning_mode,
            positioning=positioning,
        )

        existing_report = (
            self.report_repository.get_by_client_report_id(
                author_id=user.id,
                client_report_id=client_report_id,
            )
        )

        if existing_report is not None:
            return self._handle_existing_report(
                report=existing_report,
                category=category,
                longitude=longitude,
                latitude=latitude,
                observed_at=observed_at,
                description=description,
                positioning_mode=positioning_mode,
                positioning=positioning,
            )

        if positioning_mode == ReportPositioningMode.MANUAL:
            report = Report.create_manual(
                author_id=user.id,
                client_report_id=client_report_id,
                category=category,
                longitude=longitude,
                latitude=latitude,
                observed_at=observed_at,
                description=description,
            )

            saved_report = self.report_repository.save(
                report
            )

        else:
            report = Report.create_photo(
                author_id=user.id,
                client_report_id=client_report_id,
                category=category,
                longitude=longitude,
                latitude=latitude,
                observed_at=observed_at,
                description=description,
            )

            estimate = estimate_position(
                positioning
            )

            saved_report = self.report_repository.save_photo(
                report=report,
                measurements=positioning,
                estimate=estimate,
            )

        if saved_report is not None:
            return CreateReportResult(
                report=saved_report,
                created=True,
            )

        # Une autre requête a pu créer le même rapport
        # entre le SELECT et l'INSERT.
        existing_report = (
            self.report_repository.get_by_client_report_id(
                author_id=user.id,
                client_report_id=client_report_id,
            )
        )

        if existing_report is None:
            raise RuntimeError(
                "report conflict detected but report was not found"
            )

        return self._handle_existing_report(
            report=existing_report,
            category=category,
            longitude=longitude,
            latitude=latitude,
            observed_at=observed_at,
            description=description,
            positioning_mode=positioning_mode,
            positioning=positioning,
        )

    def _validate_mode(
        self,
        positioning_mode: ReportPositioningMode,
        positioning: PositioningMeasurements | None,
    ) -> None:
        if (
            positioning_mode == ReportPositioningMode.PHOTO
            and positioning is None
        ):
            raise InvalidPositioningInputError(
                "photo mode requires positioning data"
            )

        if (
            positioning_mode == ReportPositioningMode.MANUAL
            and positioning is not None
        ):
            raise InvalidPositioningInputError(
                "manual mode cannot contain positioning data"
            )

    def _handle_existing_report(
        self,
        report: Report,
        category: ReportCategory,
        longitude: float,
        latitude: float,
        observed_at: datetime,
        description: str | None,
        positioning_mode: ReportPositioningMode,
        positioning: PositioningMeasurements | None,
    ) -> CreateReportResult:
        if positioning_mode == ReportPositioningMode.MANUAL:
            matches = report.matches_manual_creation(
                category=category,
                longitude=longitude,
                latitude=latitude,
                observed_at=observed_at,
                description=description,
            )

        else:
            matches = report.matches_photo_creation(
                category=category,
                longitude=longitude,
                latitude=latitude,
                observed_at=observed_at,
                description=description,
            )

            stored_positioning = (
                self.report_repository.get_photo_positioning(
                    report.id
                )
            )

            matches = (
                matches
                and stored_positioning is not None
                and positioning is not None
                and stored_positioning.matches_measurements(
                    positioning
                )
            )

        if not matches:
            raise ReportClientIdConflictError(
                "client_report_id already used with different data"
            )

        return CreateReportResult(
            report=report,
            created=False,
        )
