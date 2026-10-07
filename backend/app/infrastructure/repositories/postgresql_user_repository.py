from app.application.ports.user_repository import UserRepository
from app.domain.user import User, UserRole, UserStatus
from app.infrastructure.database.connection import database_connection


class PostgreSQLUserRepository(UserRepository):
    def get_by_firebase_uid(self, firebase_uid: str) -> User | None:
        query = """
            SELECT
                id,
                firebase_uid,
                username,
                email,
                date_of_birth,
                nationality,
                role,
                status,
                show_user_name,
                show_boat_info,
                notifications_enabled,
                created_at,
                updated_at
            FROM nowave.users
            WHERE firebase_uid = %s
        """

        with database_connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute(query, (firebase_uid,))
                row = cursor.fetchone()

        if row is None:
            return None

        return self._row_to_user(row)

    def get_by_username(self, username: str) -> User | None:
        query = """
            SELECT
                id,
                firebase_uid,
                username,
                email,
                date_of_birth,
                nationality,
                role,
                status,
                show_user_name,
                show_boat_info,
                notifications_enabled,
                created_at,
                updated_at
            FROM nowave.users
            WHERE username = %s
        """

        with database_connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute(query, (username,))
                row = cursor.fetchone()

        if row is None:
            return None

        return self._row_to_user(row)

    def save(self, user: User) -> User:
        query = """
            INSERT INTO nowave.users (
                id,
                firebase_uid,
                username,
                email,
                date_of_birth,
                nationality,
                role,
                status,
                show_user_name,
                show_boat_info,
                notifications_enabled,
                created_at,
                updated_at
            )
            VALUES (
                %s, %s, %s, %s, %s, %s, %s,
                %s, %s, %s, %s, %s, %s
            )
        """

        values = (
            user.id,
            user.firebase_uid,
            user.username,
            user.email,
            user.date_of_birth,
            user.nationality,
            user.role.value,
            user.status.value,
            user.show_user_name,
            user.show_boat_info,
            user.notifications_enabled,
            user.created_at,
            user.updated_at,
        )

        with database_connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute(query, values)

        return user

    def update(
        self,
        user: User,
        fields: set[str] | None = None,
    ) -> User:
        allowed_fields = (
            "username",
            "date_of_birth",
            "nationality",
            "show_user_name",
            "show_boat_info",
            "notifications_enabled",
        )

        update_fields = (
            set(allowed_fields)
            if fields is None
            else set(fields)
        )

        unsupported_fields = (
            update_fields - set(allowed_fields)
        )

        if unsupported_fields:
            raise ValueError(
                "unsupported user update fields: "
                + ", ".join(sorted(unsupported_fields))
            )

        if not update_fields:
            return user

        assignments = []
        values = []

        for field in allowed_fields:
            if field not in update_fields:
                continue

            assignments.append(f"{field} = %s")
            values.append(getattr(user, field))

        assignments.append("updated_at = %s")
        values.append(user.updated_at)
        values.append(user.id)

        query = f"""
            UPDATE nowave.users
            SET {", ".join(assignments)}
            WHERE id = %s
            RETURNING
                id,
                firebase_uid,
                username,
                email,
                date_of_birth,
                nationality,
                role,
                status,
                show_user_name,
                show_boat_info,
                notifications_enabled,
                created_at,
                updated_at
        """

        with database_connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute(query, values)
                row = cursor.fetchone()

        if row is None:
            return user

        return self._row_to_user(row)

    def delete(self, user: User) -> None:
        query = """
            DELETE FROM nowave.users
            WHERE id = %s
        """

        with database_connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute(query, (user.id,))

    def _row_to_user(self, row) -> User:
        return User(
            id=row[0],
            firebase_uid=row[1],
            username=row[2],
            email=row[3],
            date_of_birth=row[4],
            nationality=row[5],
            role=UserRole(row[6]),
            status=UserStatus(row[7]),
            show_user_name=row[8],
            show_boat_info=row[9],
            notifications_enabled=row[10],
            created_at=row[11],
            updated_at=row[12],
        )
