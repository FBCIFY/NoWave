from datetime import UTC, datetime, timedelta
from uuid import uuid4

import psycopg
import pytest

from app.domain.device import Device, DevicePlatform
from app.domain.device_position import DevicePosition
from app.domain.errors import DeviceNotFoundError
from app.domain.user import User
from app.infrastructure.repositories.postgresql_device_repository import (
    PostgreSQLDeviceRepository,
)
from app.infrastructure.repositories.postgresql_user_repository import (
    PostgreSQLUserRepository,
)


def create_user():
    return User(
        firebase_uid=f"firebase-position-{uuid4()}",
        username=f"position-{uuid4()}",
        email=f"{uuid4()}@nowave.test",
    )


def create_registered_device(
    user,
    repository,
):
    device = Device(
        user_id=user.id,
        installation_id=uuid4(),
        platform=DevicePlatform.ANDROID,
    )

    return repository.register(device)


def test_save_position_creates_postgis_point(
    dsn,
    monkeypatch,
):
    monkeypatch.setenv(
        "DATABASE_URL",
        dsn,
    )

    user_repository = PostgreSQLUserRepository()
    device_repository = PostgreSQLDeviceRepository()

    user = create_user()
    user_repository.save(user)

    device = create_registered_device(
        user,
        device_repository,
    )

    measured_at = datetime.now(UTC)

    position = DevicePosition(
        device_id=device.id,
        longitude=5.37,
        latitude=43.29,
        accuracy_m=18.0,
        heading_deg=90.0,
        measured_at=measured_at,
    )

    saved = device_repository.save_position(
        position
    )

    assert saved is not None
    assert saved.device_id == device.id
    assert saved.longitude == 5.37
    assert saved.latitude == 43.29
    assert saved.accuracy_m == 18.0
    assert saved.heading_deg == 90.0

    with psycopg.connect(dsn) as connection:
        row = connection.execute(
            """
            SELECT
                ST_X(position::geometry),
                ST_Y(position::geometry),
                accuracy_m,
                heading_deg,
                measured_at,
                received_at
            FROM nowave.device_positions
            WHERE device_id = %s
            """,
            (device.id,),
        ).fetchone()

    assert row is not None
    assert row[0] == 5.37
    assert row[1] == 43.29
    assert row[2] == 18.0
    assert row[3] == 90.0
    assert row[4] == measured_at
    assert row[5] is not None


def test_newer_position_replaces_previous_position(
    dsn,
    monkeypatch,
):
    monkeypatch.setenv(
        "DATABASE_URL",
        dsn,
    )

    user_repository = PostgreSQLUserRepository()
    device_repository = PostgreSQLDeviceRepository()

    user = create_user()
    user_repository.save(user)

    device = create_registered_device(
        user,
        device_repository,
    )

    first_time = datetime.now(UTC)

    first = DevicePosition(
        device_id=device.id,
        longitude=5.37,
        latitude=43.29,
        accuracy_m=20.0,
        heading_deg=80.0,
        measured_at=first_time,
    )

    second = DevicePosition(
        device_id=device.id,
        longitude=5.38,
        latitude=43.30,
        accuracy_m=12.0,
        heading_deg=95.0,
        measured_at=first_time
        + timedelta(minutes=1),
    )

    device_repository.save_position(first)

    saved = device_repository.save_position(
        second
    )

    assert saved is not None
    assert saved.longitude == 5.38
    assert saved.latitude == 43.30
    assert saved.accuracy_m == 12.0
    assert saved.heading_deg == 95.0

    with psycopg.connect(dsn) as connection:
        row = connection.execute(
            """
            SELECT
                COUNT(*),
                MAX(measured_at)
            FROM nowave.device_positions
            WHERE device_id = %s
            """,
            (device.id,),
        ).fetchone()

        stored = connection.execute(
            """
            SELECT
                ST_X(position::geometry),
                ST_Y(position::geometry),
                accuracy_m
            FROM nowave.device_positions
            WHERE device_id = %s
            """,
            (device.id,),
        ).fetchone()

    assert row[0] == 1
    assert row[1] == second.measured_at

    assert stored[0] == 5.38
    assert stored[1] == 43.30
    assert stored[2] == 12.0


def test_older_position_does_not_replace_latest(
    dsn,
    monkeypatch,
):
    monkeypatch.setenv(
        "DATABASE_URL",
        dsn,
    )

    user_repository = PostgreSQLUserRepository()
    device_repository = PostgreSQLDeviceRepository()

    user = create_user()
    user_repository.save(user)

    device = create_registered_device(
        user,
        device_repository,
    )

    latest_time = datetime.now(UTC)

    latest = DevicePosition(
        device_id=device.id,
        longitude=5.40,
        latitude=43.31,
        accuracy_m=10.0,
        heading_deg=100.0,
        measured_at=latest_time,
    )

    older = DevicePosition(
        device_id=device.id,
        longitude=5.20,
        latitude=43.10,
        accuracy_m=15.0,
        heading_deg=50.0,
        measured_at=latest_time
        - timedelta(minutes=1),
    )

    first_result = (
        device_repository.save_position(
            latest
        )
    )

    stale_result = (
        device_repository.save_position(
            older
        )
    )

    assert first_result is not None
    assert stale_result is None

    with psycopg.connect(dsn) as connection:
        stored = connection.execute(
            """
            SELECT
                ST_X(position::geometry),
                ST_Y(position::geometry),
                accuracy_m,
                heading_deg,
                measured_at
            FROM nowave.device_positions
            WHERE device_id = %s
            """,
            (device.id,),
        ).fetchone()

    assert stored[0] == 5.40
    assert stored[1] == 43.31
    assert stored[2] == 10.0
    assert stored[3] == 100.0
    assert stored[4] == latest_time


def test_equal_measurement_timestamp_is_accepted(
    dsn,
    monkeypatch,
):
    monkeypatch.setenv(
        "DATABASE_URL",
        dsn,
    )

    user_repository = PostgreSQLUserRepository()
    device_repository = PostgreSQLDeviceRepository()

    user = create_user()
    user_repository.save(user)

    device = create_registered_device(
        user,
        device_repository,
    )

    measured_at = datetime.now(UTC)

    first = DevicePosition(
        device_id=device.id,
        longitude=5.37,
        latitude=43.29,
        accuracy_m=18.0,
        heading_deg=90.0,
        measured_at=measured_at,
    )

    retry = DevicePosition(
        device_id=device.id,
        longitude=5.37,
        latitude=43.29,
        accuracy_m=18.0,
        heading_deg=90.0,
        measured_at=measured_at,
    )

    assert (
        device_repository.save_position(first)
        is not None
    )

    result = device_repository.save_position(
        retry
    )

    assert result is not None
    assert result.measured_at == measured_at

    with psycopg.connect(dsn) as connection:
        count = connection.execute(
            """
            SELECT COUNT(*)
            FROM nowave.device_positions
            WHERE device_id = %s
            """,
            (device.id,),
        ).fetchone()[0]

    assert count == 1


def test_save_position_updates_device_last_seen_at(
    dsn,
    monkeypatch,
):
    monkeypatch.setenv(
        "DATABASE_URL",
        dsn,
    )

    user_repository = PostgreSQLUserRepository()
    device_repository = PostgreSQLDeviceRepository()

    user = create_user()
    user_repository.save(user)

    device = create_registered_device(
        user,
        device_repository,
    )

    old_last_seen = datetime(
        2026,
        1,
        1,
        tzinfo=UTC,
    )

    received_at = datetime(
        2026,
        10,
        2,
        8,
        0,
        tzinfo=UTC,
    )

    with psycopg.connect(dsn) as connection:
        connection.execute(
            """
            UPDATE nowave.devices
            SET last_seen_at = %s
            WHERE id = %s
            """,
            (
                old_last_seen,
                device.id,
            ),
        )
        connection.commit()

    position = DevicePosition(
        device_id=device.id,
        longitude=5.37,
        latitude=43.29,
        accuracy_m=18.0,
        heading_deg=90.0,
        measured_at=received_at,
        received_at=received_at,
    )

    result = device_repository.save_position(
        position
    )

    assert result is not None

    with psycopg.connect(dsn) as connection:
        last_seen_at = connection.execute(
            """
            SELECT last_seen_at
            FROM nowave.devices
            WHERE id = %s
            """,
            (device.id,),
        ).fetchone()[0]

    assert last_seen_at == received_at


def test_save_position_rejects_missing_device(dsn, monkeypatch):
    monkeypatch.setenv("DATABASE_URL", dsn)
    position = DevicePosition(
        device_id=uuid4(),
        longitude=5.37,
        latitude=43.29,
        accuracy_m=18.0,
        measured_at=datetime.now(UTC),
    )

    with pytest.raises(DeviceNotFoundError, match="active device not found"):
        PostgreSQLDeviceRepository().save_position(position)
