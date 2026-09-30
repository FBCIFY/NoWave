from uuid import UUID

from app.application.ports.report_repository import ReportRepository
from app.domain.report import (
    Report,
    ReportCategory,
    ReportPositioningMode,
    ReportStatus,
)
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
            FROM nowave.reports
            WHERE author_id = %s
              AND client_report_id = %s
        """

        values = (
            author_id,
            client_report_id,
        )

        with database_connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute(query, values)
                row = cursor.fetchone()

        if row is None:
            return None

        return self._row_to_report(row)

    def save(self, report: Report) -> Report:
        query = """
            INSERT INTO nowave.reports (
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
                %s,
                %s
            )
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

        with database_connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute(query, values)
                row = cursor.fetchone()

        return self._row_to_report(row)

    def _row_to_report(self, row) -> Report:
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
