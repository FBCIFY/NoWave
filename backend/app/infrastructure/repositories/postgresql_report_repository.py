from uuid import UUID

from app.application.ports.report_repository import ReportRepository
from app.domain.positioning import (
    PositionEstimateResult,
    PositioningMeasurements,
)
from app.domain.report import (
    Report,
    ReportCategory,
    ReportPositioningMode,
    ReportStatus,
)
from app.domain.report_photo import UploadStatus
from app.domain.report_positioning import StoredReportPositioning
from app.infrastructure.database.connection import database_connection


class PostgreSQLReportRepository(ReportRepository):
    def get_by_client_report_id(
        self,
        author_id: UUID,
        client_report_id: UUID,
    ) -> Report | None:
        query = """
            SELECT
                id,
                author_id,
                client_report_id,
                category,
                positioning_mode,
                description,
                ST_X(final_position::geometry) AS longitude,
                ST_Y(final_position::geometry) AS latitude,
                observed_at,
                status,
                version,
                created_at,
                updated_at,
                removed_at
            FROM blueway.reports
            WHERE author_id = %s
              AND client_report_id = %s
        """

        values = (
            author_id,
            client_report_id,
        )

        with database_connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    query,
                    values,
                )
                row = cursor.fetchone()

        if row is None:
            return None

        return self._row_to_report(row)

    def save(
        self,
        report: Report,
    ) -> Report | None:
        with database_connection() as connection:
            with connection.cursor() as cursor:
                row = self._insert_report(
                    cursor=cursor,
                    report=report,
                    ignore_client_conflict=True,
                )

        if row is None:
            return None

        return self._row_to_report(row)

    def save_photo(
        self,
        report: Report,
        measurements: PositioningMeasurements,
        estimate: PositionEstimateResult,
    ) -> Report | None:
        """
        Crée le rapport photo et ses deux lignes enfants
        dans une seule transaction.

        Si le même client_report_id existe déjà,
        aucune nouvelle ligne n'est créée.
        """

        with database_connection() as connection:
            with connection.cursor() as cursor:
                row = self._insert_report(
                    cursor=cursor,
                    report=report,
                    ignore_client_conflict=True,
                )

                if row is None:
                    return None

                self._insert_positioning(
                    cursor=cursor,
                    report_id=report.id,
                    measurements=measurements,
                    estimate=estimate,
                )

                self._insert_pending_photo(
                    cursor=cursor,
                    report=report,
                )

        return self._row_to_report(row)

    def get_photo_positioning(
        self,
        report_id: UUID,
    ) -> StoredReportPositioning | None:
        query = """
            SELECT
                report_id,
                ST_X(observer_position::geometry),
                ST_Y(observer_position::geometry),
                gps_accuracy_m,
                azimuth_deg,
                inclination_deg,
                camera_height_m,
                camera_height_source,
                camera_height_uncertainty_m,
                focal_length_mm,
                zoom_ratio,
                ST_X(estimated_position::geometry),
                ST_Y(estimated_position::geometry),
                estimated_distance_m,
                algorithm_version,
                captured_at
            FROM blueway.report_positioning
            WHERE report_id = %s
        """

        with database_connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    query,
                    (report_id,),
                )
                row = cursor.fetchone()

        if row is None:
            return None

        measurements = PositioningMeasurements(
            observer_longitude=row[1],
            observer_latitude=row[2],
            gps_accuracy_m=row[3],
            azimuth_deg=row[4],
            inclination_deg=row[5],
            camera_height_m=float(row[6]),
            camera_height_source=row[7],
            camera_height_uncertainty_m=row[8],
            focal_length_mm=row[9],
            zoom_ratio=row[10],
            captured_at=row[15],
        )

        return StoredReportPositioning(
            report_id=row[0],
            measurements=measurements,
            estimated_longitude=row[11],
            estimated_latitude=row[12],
            estimated_distance_m=row[13],
            algorithm_version=row[14],
        )

    def get_photo_status(
        self,
        report_id: UUID,
    ) -> UploadStatus | None:
        query = """
            SELECT upload_status
            FROM blueway.report_photos
            WHERE report_id = %s
        """

        with database_connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    query,
                    (report_id,),
                )
                row = cursor.fetchone()

        if row is None:
            return None

        return UploadStatus(row[0])

    def _insert_report(
        self,
        cursor,
        report: Report,
        ignore_client_conflict: bool,
    ):
        conflict_clause = ""

        if ignore_client_conflict:
            conflict_clause = """
                ON CONFLICT ON CONSTRAINT reports_author_client_key
                DO NOTHING
            """

        query = f"""
            INSERT INTO blueway.reports (
                id,
                author_id,
                client_report_id,
                category,
                positioning_mode,
                description,
                final_position,
                observed_at,
                created_at,
                expires_at,
                status,
                version,
                updated_at,
                removed_at
            )
            VALUES (
                %s,
                %s,
                %s,
                %s,
                %s,
                %s,
                ST_SetSRID(
                    ST_MakePoint(%s, %s),
                    4326
                )::geography,
                %s,
                %s,
                %s,
                %s,
                %s,
                %s
            )
            {conflict_clause}
            RETURNING
                id,
                author_id,
                client_report_id,
                category,
                positioning_mode,
                description,
                ST_X(final_position::geometry) AS longitude,
                ST_Y(final_position::geometry) AS latitude,
                observed_at,
                status,
                version,
                created_at,
                updated_at,
                removed_at
        """

        values = (
            report.id,
            report.author_id,
            report.client_report_id,
            report.category.value,
            report.positioning_mode.value,
            report.description,
            report.longitude,
            report.latitude,
            report.observed_at,
            report.created_at,
            report.expires_at,
            report.status.value,
            report.version,
            report.updated_at,
            report.removed_at,
        )

        cursor.execute(
            query,
            values,
        )

        return cursor.fetchone()

    def _insert_positioning(
        self,
        cursor,
        report_id: UUID,
        measurements: PositioningMeasurements,
        estimate: PositionEstimateResult,
    ) -> None:
        query = """
            INSERT INTO blueway.report_positioning (
                report_id,
                observer_position,
                gps_accuracy_m,
                azimuth_deg,
                inclination_deg,
                camera_height_m,
                camera_height_source,
                camera_height_uncertainty_m,
                focal_length_mm,
                zoom_ratio,
                estimated_position,
                estimated_distance_m,
                algorithm_version,
                captured_at
            )
            VALUES (
                %s,
                ST_SetSRID(
                    ST_MakePoint(%s, %s),
                    4326
                )::geography,
                %s,
                %s,
                %s,
                %s,
                %s,
                %s,
                %s,
                %s,
                CASE
                    WHEN %s IS NULL OR %s IS NULL
                    THEN NULL
                    ELSE ST_SetSRID(
                        ST_MakePoint(%s, %s),
                        4326
                    )::geography
                END,
                %s,
                %s,
                %s
            )
        """

        values = (
            report_id,
            measurements.observer_longitude,
            measurements.observer_latitude,
            measurements.gps_accuracy_m,
            measurements.azimuth_deg,
            measurements.inclination_deg,
            measurements.camera_height_m,
            measurements.camera_height_source,
            measurements.camera_height_uncertainty_m,
            measurements.focal_length_mm,
            measurements.zoom_ratio,
            estimate.longitude,
            estimate.latitude,
            estimate.longitude,
            estimate.latitude,
            estimate.distance_m,
            estimate.algorithm_version,
            measurements.captured_at,
        )

        cursor.execute(
            query,
            values,
        )

    def _insert_pending_photo(
        self,
        cursor,
        report: Report,
    ) -> None:
        query = """
            INSERT INTO blueway.report_photos (
                report_id,
                upload_status,
                created_at,
                updated_at
            )
            VALUES (
                %s,
                %s,
                %s,
                %s
            )
        """

        values = (
            report.id,
            UploadStatus.PENDING.value,
            report.created_at,
            report.updated_at,
        )

        cursor.execute(
            query,
            values,
        )

    def _row_to_report(
        self,
        row,
    ) -> Report:
        return Report(
            id=row[0],
            author_id=row[1],
            client_report_id=row[2],
            category=ReportCategory(row[3]),
            positioning_mode=ReportPositioningMode(row[4]),
            description=row[5],
            longitude=row[6],
            latitude=row[7],
            observed_at=row[8],
            status=ReportStatus(row[9]),
            version=row[10],
            created_at=row[11],
            updated_at=row[12],
            removed_at=row[13],
        )
