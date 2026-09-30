from uuid import UUID

from app.application.ports.report_detail_repository import (
    ReportDetailData,
    ReportDetailRepository,
)
from app.domain.report import (
    ReportCategory,
    ReportPositioningMode,
    ReportStatus,
)
from app.infrastructure.database.connection import (
    database_connection,
)


class PostgreSQLReportDetailRepository(
    ReportDetailRepository
):
    def get_by_id(
        self,
        report_id: UUID,
    ) -> ReportDetailData | None:
        query = """
            SELECT
                r.id,
                r.category,
                r.positioning_mode,
                r.description,
                ST_X(r.final_position::geometry),
                ST_Y(r.final_position::geometry),
                r.observed_at,
                r.expires_at,
                r.status,
                r.version,

                r.author_id IS NULL,

                CASE
                    WHEN u.show_user_name = TRUE
                    THEN u.username
                    ELSE NULL
                END,

                CASE
                    WHEN u.show_boat_info = TRUE
                    THEN b.name
                    ELSE NULL
                END,

                CASE
                    WHEN u.show_boat_info = TRUE
                    THEN b.boat_type
                    ELSE NULL
                END,

                rp.upload_status,
                rp.object_key,
                rp.hidden_at

            FROM blueway.reports AS r

            LEFT JOIN blueway.users AS u
                ON u.id = r.author_id

            LEFT JOIN blueway.boats AS b
                ON b.user_id = r.author_id

            LEFT JOIN blueway.report_photos AS rp
                ON rp.report_id = r.id

            WHERE r.id = %s
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

        return ReportDetailData(
            id=row[0],
            category=ReportCategory(row[1]),
            positioning_mode=ReportPositioningMode(
                row[2]
            ),
            description=row[3],
            longitude=row[4],
            latitude=row[5],
            observed_at=row[6],
            expires_at=row[7],
            status=ReportStatus(row[8]),
            version=row[9],
            author_deleted=row[10],
            author_username=row[11],
            boat_name=row[12],
            boat_type=row[13],
            photo_status=row[14],
            photo_object_key=row[15],
            photo_hidden_at=row[16],
        )
