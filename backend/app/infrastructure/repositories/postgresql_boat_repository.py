from uuid import UUID

from app.application.ports.boat_repository import BoatRepository
from app.domain.boat import Boat, BoatType
from app.domain.errors import BoatAlreadyExistsError, BoatNotFoundError
from app.infrastructure.database.connection import database_connection


class PostgreSQLBoatRepository(BoatRepository):
    def get_by_user_id(self, user_id: UUID) -> Boat | None:
        query = """
            SELECT
                id,
                user_id,
                name,
                boat_type,
                flag_country,
                created_at,
                updated_at
            FROM nowave.boats
            WHERE user_id = %s
        """

        with database_connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute(query, (user_id,))
                row = cursor.fetchone()

        if row is None:
            return None

        return self._row_to_boat(row)

    def save(self, boat: Boat) -> Boat:
        query = """
            INSERT INTO nowave.boats (
                id,
                user_id,
                name,
                boat_type,
                flag_country,
                created_at,
                updated_at
            )
            VALUES (%s, %s, %s, %s, %s, %s, %s)
            ON CONFLICT (user_id) DO NOTHING
            RETURNING id
        """

        values = (
            boat.id,
            boat.user_id,
            boat.name,
            boat.boat_type.value,
            boat.flag_country,
            boat.created_at,
            boat.updated_at,
        )

        with database_connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute(query, values)
                row = cursor.fetchone()

                if row is None:
                    raise BoatAlreadyExistsError(
                        "boat already exists"
                    )

        return boat

    def update(self, boat: Boat, *, fields: set[str]) -> Boat:
        allowed_fields = ("name", "boat_type", "flag_country")
        unsupported_fields = fields - set(allowed_fields)
        if unsupported_fields:
            raise ValueError(
                "unsupported boat update fields: "
                + ", ".join(sorted(unsupported_fields))
            )
        if not fields:
            return boat

        assignments = []
        values = []
        for field in allowed_fields:
            if field not in fields:
                continue
            assignments.append(f"{field} = %s")
            value = getattr(boat, field)
            values.append(value.value if field == "boat_type" else value)

        assignments.append("updated_at = %s")
        values.extend((boat.updated_at, boat.id))

        query = f"""
            UPDATE nowave.boats
            SET {", ".join(assignments)}
            WHERE id = %s
            RETURNING
                id,
                user_id,
                name,
                boat_type,
                flag_country,
                created_at,
                updated_at
        """

        with database_connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute(query, values)
                row = cursor.fetchone()

        if row is None:
            raise BoatNotFoundError("boat not found")
        return self._row_to_boat(row)

    def delete(self, boat: Boat) -> None:
        query = """
            DELETE FROM nowave.boats
            WHERE id = %s
        """

        with database_connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute(query, (boat.id,))

    def _row_to_boat(self, row) -> Boat:
        return Boat(
            id=row[0],
            user_id=row[1],
            name=row[2],
            boat_type=BoatType(row[3]),
            flag_country=row[4],
            created_at=row[5],
            updated_at=row[6],
        )
