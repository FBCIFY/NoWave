from datetime import UTC, datetime
from uuid import uuid4

from app.infrastructure.repositories.postgresql_device_repository import (
    PostgreSQLDeviceRepository,
)


def test_deactivate_device_cleans_runtime_data(
    db,
    dsn,
    monkeypatch,
):
    monkeypatch.setenv(
        "DATABASE_URL",
        dsn,
    )

    connection, ids = db

    now = datetime.now(UTC)

    installation_id = connection.execute(
        """
        SELECT installation_id
        FROM nowave.devices
        WHERE id = %s
        """,
        (ids["device"],),
    ).fetchone()[0]

    connection.execute(
        """
        UPDATE nowave.devices
        SET fcm_token = %s
        WHERE id = %s
        """,
        (
            "fcm-token-to-clear",
            ids["device"],
        ),
    )

    connection.execute(
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
            ids["device"],
            now,
            now,
            now,
        ),
    )

    connection.execute(
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
            ids["device"],
            now,
            now,
        ),
    )

    connection.commit()

    repository = PostgreSQLDeviceRepository()

    result = repository.deactivate(
        user_id=ids["user"],
        installation_id=installation_id,
    )

    assert result is True

    device = connection.execute(
        """
        SELECT
            is_active,
            fcm_token
        FROM nowave.devices
        WHERE id = %s
        """,
        (ids["device"],),
    ).fetchone()

    assert device[0] is False
    assert device[1] is None

    position_count = connection.execute(
        """
        SELECT COUNT(*)
        FROM nowave.device_positions
        WHERE device_id = %s
        """,
        (ids["device"],),
    ).fetchone()[0]

    assert position_count == 0

    pending_count = connection.execute(
        """
        SELECT COUNT(*)
        FROM nowave.notifications
        WHERE device_id = %s
          AND status = 'pending'
        """,
        (ids["device"],),
    ).fetchone()[0]

    assert pending_count == 0

    sent_count = connection.execute(
        """
        SELECT COUNT(*)
        FROM nowave.notifications
        WHERE device_id = %s
          AND status = 'sent'
        """,
        (ids["device"],),
    ).fetchone()[0]

    assert sent_count == 1

    failed_count = connection.execute(
        """
        SELECT COUNT(*)
        FROM nowave.notifications
        WHERE device_id = %s
          AND status = 'failed'
        """,
        (ids["device"],),
    ).fetchone()[0]

    assert failed_count == 1


def test_deactivate_device_is_idempotent(
    db,
    dsn,
    monkeypatch,
):
    monkeypatch.setenv(
        "DATABASE_URL",
        dsn,
    )

    connection, ids = db

    installation_id = connection.execute(
        """
        SELECT installation_id
        FROM nowave.devices
        WHERE id = %s
        """,
        (ids["device"],),
    ).fetchone()[0]

    repository = PostgreSQLDeviceRepository()

    first = repository.deactivate(
        user_id=ids["user"],
        installation_id=installation_id,
    )

    second = repository.deactivate(
        user_id=ids["user"],
        installation_id=installation_id,
    )

    assert first is True
    assert second is True

    state = connection.execute(
        """
        SELECT
            is_active,
            fcm_token
        FROM nowave.devices
        WHERE id = %s
        """,
        (ids["device"],),
    ).fetchone()

    assert state[0] is False
    assert state[1] is None
