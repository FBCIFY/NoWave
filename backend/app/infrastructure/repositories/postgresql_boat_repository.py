from uuid import UUID

from app.application.ports.boat_repository import BoatRepository
from app.domain.boat import Boat, BoatType
from app.domain.errors import BoatAlreadyExistsError
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
            FROM blueway.boats
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
            INSERT INTO blueway.boats (
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

    def update(self, boat: Boat) -> Boat:
        query = """
            UPDATE blueway.boats
            SET
                name = %s,
                boat_type = %s,
                flag_country = %s,
                updated_at = %s
            WHERE id = %s
        """

        values = (
            boat.name,
            boat.boat_type.value,
            boat.flag_country,
            boat.updated_at,
            boat.id,
        )

        with database_connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute(query, values)

        return boat

    def delete(self, boat: Boat) -> None:
        query = """
            DELETE FROM blueway.boats
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
