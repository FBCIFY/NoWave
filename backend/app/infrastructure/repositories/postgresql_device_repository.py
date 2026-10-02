from uuid import UUID

from psycopg.errors import UniqueViolation

from app.application.ports.device_repository import (
    DeviceRepository,
)
from app.domain.device import Device, DevicePlatform
from app.domain.device_position import DevicePosition
from app.domain.errors import DeviceConflictError
from app.infrastructure.database.connection import (
    database_connection,
)


class PostgreSQLDeviceRepository(DeviceRepository):
    def register(self, device: Device) -> Device:
        query = """
            INSERT INTO nowave.devices (
                id,
                user_id,
                installation_id,
                fcm_token,
                platform,
                is_active,
                last_seen_at
            )
            VALUES (
                %s, %s, %s, %s, %s, %s, %s
            )
            ON CONFLICT (installation_id)
            DO UPDATE SET
                fcm_token = EXCLUDED.fcm_token,
                platform = EXCLUDED.platform,
                is_active = TRUE,
                last_seen_at = EXCLUDED.last_seen_at
            WHERE
                nowave.devices.user_id
                = EXCLUDED.user_id
            RETURNING
                id,
                user_id,
                installation_id,
                fcm_token,
                platform,
                is_active,
                last_seen_at
        """

        values = (
            device.id,
            device.user_id,
            device.installation_id,
            device.fcm_token,
            device.platform.value,
            device.is_active,
            device.last_seen_at,
        )

        try:
            with database_connection() as connection:
                with connection.cursor() as cursor:
                    cursor.execute(query, values)
                    row = cursor.fetchone()

                    if row is None:
                        raise DeviceConflictError(
                            "installation belongs "
                            "to another user"
                        )

        except UniqueViolation as error:
            raise DeviceConflictError(
                "fcm token already assigned "
                "to another device"
            ) from error

        return self._row_to_device(row)

    def get_active_by_user_and_installation(
        self,
        user_id: UUID,
        installation_id: UUID,
    ) -> Device | None:
        query = """
            SELECT
                id,
                user_id,
                installation_id,
                fcm_token,
                platform,
                is_active,
                last_seen_at
            FROM nowave.devices
            WHERE user_id = %s
              AND installation_id = %s
              AND is_active = TRUE
        """

        with database_connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    query,
                    (
                        user_id,
                        installation_id,
                    ),
                )
                row = cursor.fetchone()

        if row is None:
            return None

        return self._row_to_device(row)

    def save_position(
        self,
        position: DevicePosition,
    ) -> DevicePosition | None:
        query = """
            INSERT INTO nowave.device_positions (
                device_id,
                position,
                accuracy_m,
                heading_deg,
                measured_at,
                received_at
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
                %s
            )
            ON CONFLICT (device_id)
            DO UPDATE SET
                position = EXCLUDED.position,
                accuracy_m = EXCLUDED.accuracy_m,
                heading_deg = EXCLUDED.heading_deg,
                measured_at = EXCLUDED.measured_at,
                received_at = EXCLUDED.received_at
            WHERE
                EXCLUDED.measured_at
                >= nowave.device_positions.measured_at
            RETURNING
                device_id,
                ST_X(position::geometry),
                ST_Y(position::geometry),
                accuracy_m,
                heading_deg,
                measured_at,
                received_at
        """

        values = (
            position.device_id,
            position.longitude,
            position.latitude,
            position.accuracy_m,
            position.heading_deg,
            position.measured_at,
            position.received_at,
        )

        with database_connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute(query, values)
                row = cursor.fetchone()

                if row is not None:
                    cursor.execute(
                        """
                        UPDATE nowave.devices
                        SET last_seen_at = %s
                        WHERE id = %s
                        """,
                        (
                            position.received_at,
                            position.device_id,
                        ),
                    )

        if row is None:
            return None

        return DevicePosition(
            device_id=row[0],
            longitude=row[1],
            latitude=row[2],
            accuracy_m=row[3],
            heading_deg=row[4],
            measured_at=row[5],
            received_at=row[6],
        )

    def deactivate(
        self,
        user_id: UUID,
        installation_id: UUID,
    ) -> bool:
        with database_connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    """
                    SELECT id
                    FROM nowave.devices
                    WHERE user_id = %s
                      AND installation_id = %s
                    FOR UPDATE
                    """,
                    (
                        user_id,
                        installation_id,
                    ),
                )

                row = cursor.fetchone()

                if row is None:
                    return False

                device_id = row[0]

                cursor.execute(
                    """
                    SELECT id
                    FROM nowave.notifications
                    WHERE device_id = %s
                      AND status = 'pending'
                    FOR UPDATE
                    """,
                    (device_id,),
                )

                cursor.fetchall()

                cursor.execute(
                    """
                    DELETE FROM nowave.notifications
                    WHERE device_id = %s
                      AND status = 'pending'
                    """,
                    (device_id,),
                )

                cursor.execute(
                    """
                    DELETE FROM nowave.device_positions
                    WHERE device_id = %s
                    """,
                    (device_id,),
                )

                cursor.execute(
                    """
                    UPDATE nowave.devices
                    SET
                        is_active = FALSE,
                        fcm_token = NULL
                    WHERE id = %s
                    """,
                    (device_id,),
                )

        return True

    def _row_to_device(self, row) -> Device:
        return Device(
            id=row[0],
            user_id=row[1],
            installation_id=row[2],
            fcm_token=row[3],
            platform=DevicePlatform(row[4]),
            is_active=row[5],
            last_seen_at=row[6],
        )
