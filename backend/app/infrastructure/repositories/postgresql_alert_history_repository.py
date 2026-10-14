from uuid import UUID

from app.application.ports.alert_history_repository import (
    AlertHistoryRepository,
)
from app.domain.alert import Alert
from app.domain.pagination import Page, page_offset
from app.domain.report import ReportCategory
from app.infrastructure.database.connection import (
    database_connection,
)


class PostgreSQLAlertHistoryRepository(
    AlertHistoryRepository
):
    def list_for_user(
        self,
        user_id: UUID,
        page: int,
        limit: int,
    ) -> Page[Alert]:
        count_query = """
            SELECT count(*)
            FROM nowave.alert_history
            WHERE user_id = %(user_id)s
        """

        # Position and category come from the history row: the
        # alerted version, even if the report changed since.
        items_query = """
            SELECT
                id,
                report_id,
                report_version,
                category,
                ST_X(position::geometry),
                ST_Y(position::geometry),
                distance_m,
                alerted_at
            FROM nowave.alert_history
            WHERE user_id = %(user_id)s
            ORDER BY alerted_at DESC, id DESC
            LIMIT %(limit)s
            OFFSET %(offset)s
        """

        # Count and page in one read-only snapshot, so total and
        # items cannot disagree after a concurrent publication.
        with database_connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    "SET TRANSACTION ISOLATION LEVEL "
                    "REPEATABLE READ READ ONLY"
                )

                cursor.execute(
                    count_query,
                    {"user_id": user_id},
                )
                total = cursor.fetchone()[0]

                cursor.execute(
                    items_query,
                    {
                        "user_id": user_id,
                        "limit": limit,
                        "offset": page_offset(page, limit),
                    },
                )
                rows = cursor.fetchall()

        return Page(
            items=[
                Alert(
                    id=row[0],
                    report_id=row[1],
                    report_version=row[2],
                    category=ReportCategory(row[3]),
                    longitude=row[4],
                    latitude=row[5],
                    distance_m=row[6],
                    alerted_at=row[7],
                )
                for row in rows
            ],
            page=page,
            limit=limit,
            total=total,
        )
