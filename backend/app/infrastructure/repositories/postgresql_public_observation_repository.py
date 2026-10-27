from app.application.ports.public_observation_reader import (
    ObservationQuery,
    PublicObservation,
    PublicObservationReader,
)
from app.domain.report import ReportCategory
from app.infrastructure.database.connection import database_connection


class PostgreSQLPublicObservationRepository(PublicObservationReader):
    def list_active(self, query: ObservationQuery) -> list[PublicObservation]:
        clauses = [
            "r.status = 'active'",
            "r.expires_at > statement_timestamp()",
            "r.removed_at IS NULL",
        ]
        values = []
        # Each envelope stays on one side of the dateline and retains the
        # spatial-index predicate. A wrapped box includes the two outer bands.
        envelopes = (
            [(query.west, query.south, query.east, query.north)]
            if query.west <= query.east else [
                (query.west, query.south, 180, query.north),
                (-180, query.south, query.east, query.north),
            ]
        )
        clauses.append("(" + " OR ".join(
            "r.final_position::geometry && ST_MakeEnvelope(%s, %s, %s, %s, 4326)"
            for _ in envelopes
        ) + ")")
        for envelope in envelopes:
            values.extend(envelope)
        if query.category is not None:
            clauses.append("r.category = %s")
            values.append(query.category.value)
        if query.q:
            # Treat %, _ and backslash literally, and never search a hidden
            # username: even the existence of a result could expose it.
            search = "%" + query.q.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") + "%"
            clauses.append("(r.description ILIKE %s OR (u.show_user_name = TRUE AND u.username ILIKE %s))")
            values.extend([search, search])
        if query.after is not None:
            clauses.append("(r.observed_at, r.id) < (%s, %s)")
            values.extend(query.after)
        values.append(query.limit + 1)
        statement = """
            SELECT r.id, r.category,
                ST_X(r.final_position::geometry), ST_Y(r.final_position::geometry),
                r.observed_at, r.expires_at,
                NULLIF(BTRIM(r.description), ''),
                CASE WHEN u.show_user_name = TRUE THEN NULLIF(BTRIM(u.username), '') END
            FROM nowave.reports AS r
            LEFT JOIN nowave.users AS u ON u.id = r.author_id
            WHERE """ + " AND ".join(clauses) + """
            ORDER BY r.observed_at DESC, r.id DESC
            LIMIT %s
        """
        with database_connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute(statement, values)
                rows = cursor.fetchall()
        return [PublicObservation(
            id=row[0], category=ReportCategory(row[1]),
            longitude=row[2], latitude=row[3],
            observed_at=row[4], expires_at=row[5],
            description=row[6], author_username=row[7],
        ) for row in rows]
