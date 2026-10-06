from datetime import UTC, datetime
from uuid import uuid4

from fastapi.testclient import TestClient
import psycopg
from psycopg import sql
from psycopg.conninfo import make_conninfo

from app.api.dependencies.auth import get_current_identity
from app.infrastructure.database.runtime_permissions import (
    grant_runtime_table_permissions,
)
from app.main import app


def test_device_routes_work_with_runtime_role(
    db,
    dsn,
    monkeypatch,
):
    connection, ids = db

    firebase_uid = connection.execute(
        """
        SELECT firebase_uid
        FROM nowave.users
        WHERE id = %s
        """,
        (ids["user"],),
    ).fetchone()[0]

    connection.commit()

    role_name = "nw113_runtime_" + uuid4().hex
    role = sql.Identifier(role_name)

    with psycopg.connect(
        dsn,
        autocommit=True,
    ) as admin:
        admin.execute(
            sql.SQL(
                "CREATE ROLE {} "
                "NOSUPERUSER NOCREATEDB NOCREATEROLE"
            ).format(role)
        )

        try:
            grant_runtime_table_permissions(
                admin,
                role_name,
            )

            runtime_dsn = make_conninfo(
                dsn,
                options=f"-c role={role_name}",
            )

            monkeypatch.setenv(
                "DATABASE_URL",
                runtime_dsn,
            )

            app.dependency_overrides[
                get_current_identity
            ] = lambda: {
                "uid": firebase_uid,
            }

            client = TestClient(app)
            installation_id = uuid4()

            register = client.put(
                "/api/v1/devices/current",
                json={
                    "installation_id": str(
                        installation_id
                    ),
                    "platform": "ios",
                    "fcm_token": (
                        "nw113-runtime-token"
                    ),
                },
            )

            assert register.status_code == 200

            device_id = register.json()["id"]
            now = datetime.now(UTC)

            admin.execute(
                """
                INSERT INTO nowave.notifications (
                    id,
                    report_id,
                    device_id,
                    report_version,
                    status,
                    attempt_count,
                    next_attempt_at,
                    sent_at,
                    created_at,
                    updated_at
                )
                VALUES (
                    %s, %s, %s, 1,
                    'pending', 0,
                    %s, NULL, %s, %s
                )
                """,
                (
                    uuid4(),
                    ids["report"],
                    device_id,
                    now,
                    now,
                    now,
                ),
            )

            admin.execute(
                """
                INSERT INTO nowave.notifications (
                    id,
                    report_id,
                    device_id,
                    report_version,
                    status,
                    attempt_count,
                    next_attempt_at,
                    sent_at,
                    created_at,
                    updated_at
                )
                VALUES (
                    %s, %s, %s, 2,
                    'sent', 1,
                    NULL, %s, %s, %s
                )
                """,
                (
                    uuid4(),
                    ids["report"],
                    device_id,
                    now,
                    now,
                    now,
                ),
            )

            admin.execute(
                """
                INSERT INTO nowave.notifications (
                    id,
                    report_id,
                    device_id,
                    report_version,
                    status,
                    attempt_count,
                    next_attempt_at,
                    sent_at,
                    created_at,
                    updated_at
                )
                VALUES (
                    %s, %s, %s, 3,
                    'failed', 1,
                    NULL, NULL, %s, %s
                )
                """,
                (
                    uuid4(),
                    ids["report"],
                    device_id,
                    now,
                    now,
                ),
            )

            position = client.put(
                "/api/v1/devices/current/position",
                headers={
                    "X-Installation-ID": str(
                        installation_id
                    ),
                },
                json={
                    "position": {
                        "type": "Point",
                        "coordinates": [
                            5.37,
                            43.29,
                        ],
                    },
                    "accuracy_m": 50,
                    "heading_deg": 90,
                    "measured_at": (
                        now.isoformat()
                    ),
                },
            )

            assert position.status_code == 200
            assert (
                position.json()["accuracy_m"]
                == 50
            )

            deactivate = client.delete(
                "/api/v1/devices/current",
                headers={
                    "X-Installation-ID": str(
                        installation_id
                    ),
                },
            )

            assert deactivate.status_code == 204

            device = admin.execute(
                """
                SELECT is_active, fcm_token
                FROM nowave.devices
                WHERE id = %s
                """,
                (device_id,),
            ).fetchone()

            assert device == (False, None)

            position_count = admin.execute(
                """
                SELECT COUNT(*)
                FROM nowave.device_positions
                WHERE device_id = %s
                """,
                (device_id,),
            ).fetchone()[0]

            assert position_count == 0

            statuses = dict(
                admin.execute(
                    """
                    SELECT status, COUNT(*)
                    FROM nowave.notifications
                    WHERE device_id = %s
                    GROUP BY status
                    """,
                    (device_id,),
                ).fetchall()
            )

            assert statuses.get("pending", 0) == 0
            assert statuses.get("sent", 0) == 1
            assert statuses.get("failed", 0) == 1

            assert not admin.execute(
                """
                SELECT has_table_privilege(
                    %s,
                    'nowave.devices',
                    'DELETE'
                )
                """,
                (role_name,),
            ).fetchone()[0]

            assert not admin.execute(
                """
                SELECT has_table_privilege(
                    %s,
                    'nowave.notifications',
                    'INSERT'
                )
                """,
                (role_name,),
            ).fetchone()[0]

        finally:
            app.dependency_overrides.clear()

            admin.execute(
                sql.SQL(
                    "DROP OWNED BY {}"
                ).format(role)
            )

            admin.execute(
                sql.SQL(
                    "DROP ROLE {}"
                ).format(role)
            )
