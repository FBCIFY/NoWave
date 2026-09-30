from datetime import UTC, datetime, timedelta
from enum import Enum
from math import isfinite
from uuid import UUID, uuid4

from app.domain.errors import (
    InvalidObservedAtError,
    InvalidReportCategoryError,
    InvalidReportDescriptionError,
    InvalidReportPositionError,
)


class ReportCategory(str, Enum):
    MARINE_ANIMAL = "marine_animal"
    OBSTRUCTION = "obstruction"
    POLLUTION = "pollution"


class ReportPositioningMode(str, Enum):
    MANUAL = "manual"
    PHOTO = "photo"


class ReportStatus(str, Enum):
    ACTIVE = "active"
    EXPIRED = "expired"
    REMOVED = "removed"


class Report:
    def __init__(
        self,
        author_id: UUID | None,
        client_report_id: UUID,
        category: ReportCategory,
        longitude: float,
        latitude: float,
        observed_at: datetime,
        description: str | None = None,
        positioning_mode: ReportPositioningMode = ReportPositioningMode.MANUAL,
        id: UUID | None = None,
        status: ReportStatus = ReportStatus.ACTIVE,
        version: int = 1,
        created_at: datetime | None = None,
        updated_at: datetime | None = None,
        removed_at: datetime | None = None,
    ):

        if client_report_id is None:
            raise ValueError("client_report_id is required")

        try:
            category = ReportCategory(category)
        except ValueError as error:
            raise InvalidReportCategoryError(
                "invalid report category"
            ) from error

        if description is not None and len(description) > 250:
            raise InvalidReportDescriptionError(
                "description cannot exceed 250 characters"
            )

        if not isfinite(longitude) or not -180 <= longitude <= 180:
            raise InvalidReportPositionError(
                "longitude must be between -180 and 180"
            )

        if not isfinite(latitude) or not -90 <= latitude <= 90:
            raise InvalidReportPositionError(
                "latitude must be between -90 and 90"
            )

        if observed_at.tzinfo is None or observed_at.utcoffset() is None:
            raise InvalidObservedAtError(
                "observed_at must include a timezone"
            )

        observed_at = observed_at.astimezone(UTC)

        try:
            positioning_mode = ReportPositioningMode(positioning_mode)
        except ValueError as error:
            raise ValueError(
                "invalid positioning mode"
            ) from error

        self.id = id if id is not None else uuid4()
        self.author_id = author_id
        self.client_report_id = client_report_id
        self.category = category
        self.positioning_mode = positioning_mode
        self.description = description
        self.longitude = longitude
        self.latitude = latitude
        self.observed_at = observed_at
        self.expires_at = observed_at + timedelta(hours=24)
        self.status = ReportStatus(status)
        self.version = version

        now = datetime.now(UTC)

        self.created_at = created_at if created_at is not None else now
        self.updated_at = updated_at if updated_at is not None else now
        self.removed_at = removed_at

    @classmethod
    def create_manual(
        cls,
        author_id: UUID,
        client_report_id: UUID,
        category: ReportCategory,
        longitude: float,
        latitude: float,
        observed_at: datetime,
        description: str | None = None,
    ) -> "Report":
        if observed_at.tzinfo is None or observed_at.utcoffset() is None:
            raise InvalidObservedAtError(
                "observed_at must include a timezone"
            )

        observed_at = observed_at.astimezone(UTC)
        now = datetime.now(UTC)

        if author_id is None:
                    raise ValueError("author_id is required")
        
        if observed_at > now:
            raise InvalidObservedAtError(
                "observed_at cannot be in the future"
            )

        if observed_at < now - timedelta(hours=24):
            raise InvalidObservedAtError(
                "observed_at cannot be older than 24 hours"
            )

        return cls(
            author_id=author_id,
            client_report_id=client_report_id,
            category=category,
            longitude=longitude,
            latitude=latitude,
            observed_at=observed_at,
            description=description,
            positioning_mode=ReportPositioningMode.MANUAL,
            status=ReportStatus.ACTIVE,
            version=1,
            created_at=now,
            updated_at=now,
        )

    @classmethod
    def create_photo(
        cls,
        author_id: UUID,
        client_report_id: UUID,
        category: ReportCategory,
        longitude: float,
        latitude: float,
        observed_at: datetime,
        description: str | None = None,
    ) -> "Report":
        if observed_at.tzinfo is None or observed_at.utcoffset() is None:
            raise InvalidObservedAtError(
                "observed_at must include a timezone"
            )

        observed_at = observed_at.astimezone(UTC)
        now = datetime.now(UTC)

        if author_id is None:
            raise ValueError(
                "author_id is required"
            )

        if observed_at > now:
            raise InvalidObservedAtError(
                "observed_at cannot be in the future"
            )

        if observed_at < now - timedelta(hours=24):
            raise InvalidObservedAtError(
                "observed_at cannot be older than 24 hours"
            )

        return cls(
            author_id=author_id,
            client_report_id=client_report_id,
            category=category,
            longitude=longitude,
            latitude=latitude,
            observed_at=observed_at,
            description=description,
            positioning_mode=ReportPositioningMode.PHOTO,
            status=ReportStatus.ACTIVE,
            version=1,
            created_at=now,
            updated_at=now,
        )

    def matches_photo_creation(
        self,
        category: ReportCategory,
        longitude: float,
        latitude: float,
        observed_at: datetime,
        description: str | None,
    ) -> bool:
        if observed_at.tzinfo is None or observed_at.utcoffset() is None:
            return False

        try:
            category = ReportCategory(
                category
            )
        except ValueError:
            return False

        observed_at = observed_at.astimezone(
            UTC
        )

        return (
            self.positioning_mode
            == ReportPositioningMode.PHOTO
            and self.category == category
            and self.longitude == longitude
            and self.latitude == latitude
            and self.observed_at == observed_at
            and self.description == description
        )

    def matches_manual_creation(
        self,
        category: ReportCategory,
        longitude: float,
        latitude: float,
        observed_at: datetime,
        description: str | None,
    ) -> bool:
        if observed_at.tzinfo is None or observed_at.utcoffset() is None:
            return False

        try:
            category = ReportCategory(category)
        except ValueError:
            return False

        observed_at = observed_at.astimezone(UTC)

        return (
            self.positioning_mode == ReportPositioningMode.MANUAL
            and self.category == category
            and self.longitude == longitude
            and self.latitude == latitude
            and self.observed_at == observed_at
            and self.description == description
        )
