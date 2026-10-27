from datetime import UTC, datetime
from uuid import UUID

from app.application.ports.admin_read_repository import (
    AdminReadRepository,
    AdminReportDetailData,
    AdminReportSummaryData,
    AdminUserData,
    ModerationActionData,
)
from app.domain.boat import BoatType
from app.domain.moderation import ModerationActionType
from app.domain.pagination import Page, page_offset
from app.domain.report import (
    ReportCategory,
    ReportPositioningMode,
    ReportStatus,
)
from app.domain.report_photo import UploadStatus
from app.domain.user import UserRole, UserStatus
from app.infrastructure.database.connection import (
    database_connection,
)


# No job rewrites expired rows: an active report past expires_at is
# shown as expired, matching the map and the public detail, which
# already hide it.
EFFECTIVE_REPORT_STATUS = """
    CASE
        WHEN r.status = 'active'
            AND r.expires_at <= %(now)s
        THEN 'expired'
        ELSE r.status
    END
"""


class PostgreSQLAdminReadRepository(
    AdminReadRepository
):
    def search_users(self, page: int, status: UserStatus | None, search: str, limit: int = 20):
        query = """
            SELECT u.id, u.username, u.email, u.role, u.status,
                   u.created_at, u.updated_at,
                   (SELECT count(*) FROM nowave.reports r WHERE r.author_id = u.id)
            FROM nowave.users u
            WHERE (%(status)s::text IS NULL OR u.status = %(status)s)
              AND (u.username ILIKE %(search)s OR u.email ILIKE %(search)s
                   OR u.id::text = %(exact)s)
            ORDER BY u.created_at DESC, u.id DESC
            LIMIT %(limit)s OFFSET %(offset)s
        """
        count = """
            SELECT count(*) FROM nowave.users u
            WHERE (%(status)s::text IS NULL OR u.status = %(status)s)
              AND (u.username ILIKE %(search)s OR u.email ILIKE %(search)s
                   OR u.id::text = %(exact)s)
        """
        escaped = search.replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_')
        params = {"status": status.value if status else None,
                  "search": f"%{escaped}%", "exact": search,
                  "offset": page_offset(page, limit), "limit": limit}
        with database_connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute(count, params)
                total = cursor.fetchone()[0]
                cursor.execute(query, params)
                rows = cursor.fetchall()
        return rows, total

    def user_reports(self, user_id: UUID, page: int):
        """One bounded page and a lookahead, without a separate count query."""
        offset = page_offset(page, 20)
        query = f"""
            SELECT r.id, r.category, {EFFECTIVE_REPORT_STATUS}, r.observed_at,
                   r.description, u.username
            FROM nowave.reports r
            LEFT JOIN nowave.users u ON u.id = r.author_id
            WHERE r.author_id = %(user_id)s
            ORDER BY r.observed_at DESC, r.id DESC LIMIT 21 OFFSET %(offset)s
        """
        with database_connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute(query, {"user_id": user_id, "offset": offset,
                                       "now": datetime.now(UTC)})
                rows = cursor.fetchall()
        return rows[:20], len(rows) > 20

    def map_reports(self, west: float, south: float, east: float, north: float, limit: int = 1000):
        """Bounded administrative map read. Extra row signals truncation."""
        limit = max(1, min(limit, 1000))
        query = f"""
            SELECT r.id, ST_X(r.final_position::geometry),
                   ST_Y(r.final_position::geometry), r.category,
                   {EFFECTIVE_REPORT_STATUS}
            FROM nowave.reports AS r
            WHERE r.final_position && ST_MakeEnvelope(
                %(west)s, %(south)s, %(east)s, %(north)s, 4326)::geography
            ORDER BY r.observed_at DESC, r.id DESC
            LIMIT %(limit)s
        """
        with database_connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute(query, {"west": west, "south": south,
                    "east": east, "north": north, "now": datetime.now(UTC),
                    "limit": limit + 1})
                rows = cursor.fetchall()
        return rows[:limit], len(rows) > limit

    def list_reports(
        self,
        page: int,
        limit: int,
        status: ReportStatus | None,
        now: datetime,
        search: str = "",
    ) -> Page[AdminReportSummaryData]:
        filters = f"""
            WHERE (
                %(status)s::text IS NULL
                OR ({EFFECTIVE_REPORT_STATUS}) = %(status)s
            )
        """

        if search:
            filters += """
                AND (r.description ILIKE %(search)s
                     OR r.id::text = %(exact_search)s
                     OR EXISTS (
                         SELECT 1 FROM nowave.users AS author
                         WHERE author.id = r.author_id
                           AND author.username ILIKE %(search)s
                     ))
            """
        escaped_search = search.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")

        count_query = f"""
            SELECT count(*)
            FROM nowave.reports AS r
            {filters}
        """

        items_query = f"""
            SELECT
                r.id,
                r.category,
                r.positioning_mode,
                {EFFECTIVE_REPORT_STATUS},
                r.observed_at,
                r.expires_at,
                r.removed_at,
                r.version,
                r.author_id,
                u.username,
                rp.upload_status,
                rp.hidden_at,
                r.description

            FROM nowave.reports AS r

            LEFT JOIN nowave.users AS u
                ON u.id = r.author_id

            LEFT JOIN nowave.report_photos AS rp
                ON rp.report_id = r.id

            {filters}

            ORDER BY r.observed_at DESC, r.id DESC
            LIMIT %(limit)s
            OFFSET %(offset)s
        """

        total, rows = self._read_page(
            count_query=count_query,
            items_query=items_query,
            page=page,
            limit=limit,
            params={
                "status": (
                    status.value
                    if status is not None
                    else None
                ),
                "now": now,
                "search": f"%{escaped_search}%",
                "exact_search": search,
            },
        )

        return Page(
            items=[
                AdminReportSummaryData(
                    id=row[0],
                    category=ReportCategory(row[1]),
                    positioning_mode=ReportPositioningMode(
                        row[2]
                    ),
                    status=ReportStatus(row[3]),
                    observed_at=row[4],
                    expires_at=row[5],
                    removed_at=row[6],
                    version=row[7],
                    author_id=row[8],
                    author_username=row[9],
                    photo_status=(
                        UploadStatus(row[10])
                        if row[10] is not None
                        else None
                    ),
                    photo_hidden_at=row[11],
                    description=row[12],
                )
                for row in rows
            ],
            page=page,
            limit=limit,
            total=total,
        )

    def get_report(
        self,
        report_id: UUID,
        now: datetime,
    ) -> AdminReportDetailData | None:
        query = f"""
            SELECT
                r.id,
                r.category,
                r.positioning_mode,
                r.description,
                ST_X(r.final_position::geometry),
                ST_Y(r.final_position::geometry),
                r.observed_at,
                r.expires_at,
                {EFFECTIVE_REPORT_STATUS},
                r.version,
                r.removed_at,

                r.author_id,
                u.username,
                u.email,
                u.status,

                b.name,
                b.boat_type,

                rp.upload_status,
                rp.object_key,
                rp.hidden_at

            FROM nowave.reports AS r

            LEFT JOIN nowave.users AS u
                ON u.id = r.author_id

            LEFT JOIN nowave.boats AS b
                ON b.user_id = r.author_id

            LEFT JOIN nowave.report_photos AS rp
                ON rp.report_id = r.id

            WHERE r.id = %(report_id)s
        """

        with database_connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    query,
                    {
                        "report_id": report_id,
                        "now": now,
                    },
                )

                row = cursor.fetchone()

        if row is None:
            return None

        return AdminReportDetailData(
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
            removed_at=row[10],
            author_deleted=row[11] is None,
            author_id=row[11],
            author_username=row[12],
            author_email=row[13],
            author_status=(
                UserStatus(row[14])
                if row[14] is not None
                else None
            ),
            boat_name=row[15],
            boat_type=(
                BoatType(row[16])
                if row[16] is not None
                else None
            ),
            photo_status=(
                UploadStatus(row[17])
                if row[17] is not None
                else None
            ),
            photo_object_key=row[18],
            photo_hidden_at=row[19],
        )

    def list_users(
        self,
        page: int,
        limit: int,
        status: UserStatus | None,
    ) -> Page[AdminUserData]:
        filters = """
            WHERE (
                %(status)s::text IS NULL
                OR u.status = %(status)s
            )
        """

        count_query = f"""
            SELECT count(*)
            FROM nowave.users AS u
            {filters}
        """

        items_query = f"""
            SELECT
                u.id,
                u.username,
                u.email,
                u.role,
                u.status,
                u.created_at,
                u.updated_at,
                (
                    SELECT count(*)
                    FROM nowave.reports AS r
                    WHERE r.author_id = u.id
                )

            FROM nowave.users AS u

            {filters}

            ORDER BY u.created_at DESC, u.id DESC
            LIMIT %(limit)s
            OFFSET %(offset)s
        """

        total, rows = self._read_page(
            count_query=count_query,
            items_query=items_query,
            page=page,
            limit=limit,
            params={
                "status": (
                    status.value
                    if status is not None
                    else None
                ),
            },
        )

        return Page(
            items=[
                AdminUserData(
                    id=row[0],
                    username=row[1],
                    email=row[2],
                    role=UserRole(row[3]),
                    status=UserStatus(row[4]),
                    created_at=row[5],
                    updated_at=row[6],
                    reports_count=row[7],
                )
                for row in rows
            ],
            page=page,
            limit=limit,
            total=total,
        )

    def list_moderation_actions(
        self,
        page: int,
        limit: int,
        report_id: UUID | None = None,
    ) -> Page[ModerationActionData]:
        filters = """
            WHERE (
                %(report_id)s::uuid IS NULL
                OR m.target_report_id = %(report_id)s
                OR m.target_photo_report_id = %(report_id)s
            )
        """

        count_query = f"""
            SELECT count(*)
            FROM nowave.moderation_actions AS m
            {filters}
        """

        items_query = f"""
            SELECT
                m.id,
                m.action,
                m.admin_user_id,
                a.username,
                m.target_user_id,
                m.target_report_id,
                m.target_photo_report_id,
                m.reason,
                m.previous_status,
                m.new_status,
                m.created_at

            FROM nowave.moderation_actions AS m

            LEFT JOIN nowave.users AS a
                ON a.id = m.admin_user_id

            {filters}

            ORDER BY m.created_at DESC, m.id DESC
            LIMIT %(limit)s
            OFFSET %(offset)s
        """

        total, rows = self._read_page(
            count_query=count_query,
            items_query=items_query,
            page=page,
            limit=limit,
            params={"report_id": report_id},
        )

        return Page(
            items=[
                ModerationActionData(
                    id=row[0],
                    action=ModerationActionType(row[1]),
                    admin_user_id=row[2],
                    admin_username=row[3],
                    target_user_id=row[4],
                    target_report_id=row[5],
                    target_photo_report_id=row[6],
                    reason=row[7],
                    previous_status=row[8],
                    new_status=row[9],
                    created_at=row[10],
                )
                for row in rows
            ],
            page=page,
            limit=limit,
            total=total,
        )

    def _read_page(
        self,
        count_query: str,
        items_query: str,
        page: int,
        limit: int,
        params: dict,
    ) -> tuple[int, list[tuple]]:
        """Run the count and the page in one read-only snapshot, so total
        and items cannot disagree after a concurrent write."""
        with database_connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    "SET TRANSACTION ISOLATION LEVEL "
                    "REPEATABLE READ READ ONLY"
                )

                cursor.execute(count_query, params)
                total = cursor.fetchone()[0]

                cursor.execute(
                    items_query,
                    {
                        **params,
                        "limit": limit,
                        "offset": page_offset(page, limit),
                    },
                )
                rows = cursor.fetchall()

        return total, rows
