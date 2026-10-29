from uuid import uuid4

import psycopg
import pytest

from app.domain.device import Device, DevicePlatform
from app.domain.errors import DeviceConflictError
from app.domain.user import User
from app.infrastructure.repositories.postgresql_device_repository import (
    PostgreSQLDeviceRepository,
)
from app.infrastructure.repositories.postgresql_user_repository import (
    PostgreSQLUserRepository,
)


def create_user():
    return User(
        firebase_uid=f"firebase-device-{uuid4()}",
        username=f"device-{uuid4()}",
        email=f"{uuid4()}@nowave.test",
    )


def test_register_device_creates_device(
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

    installation_id = uuid4()

    device = Device(
        user_id=user.id,
        installation_id=installation_id,
        platform=DevicePlatform.ANDROID,
        fcm_token="fcm-token-a",
    )

    saved_device = device_repository.register(device)

    assert saved_device.user_id == user.id
    assert saved_device.installation_id == installation_id
    assert saved_device.platform == DevicePlatform.ANDROID
    assert saved_device.fcm_token == "fcm-token-a"
    assert saved_device.is_active is True

    with psycopg.connect(dsn) as connection:
        row = connection.execute(
            """
            SELECT
                user_id,
                installation_id,
                fcm_token,
                platform,
                is_active
            FROM nowave.devices
            WHERE installation_id = %s
            """,
            (installation_id,),
        ).fetchone()

    assert row is not None
    assert row[0] == user.id
    assert row[1] == installation_id
    assert row[2] == "fcm-token-a"
    assert row[3] == "android"
    assert row[4] is True


def test_register_same_installation_is_idempotent(
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

    installation_id = uuid4()

    first = device_repository.register(
        Device(
            user_id=user.id,
            installation_id=installation_id,
            platform=DevicePlatform.ANDROID,
            fcm_token="fcm-token-old",
        )
    )

    second = device_repository.register(
        Device(
            user_id=user.id,
            installation_id=installation_id,
            platform=DevicePlatform.ANDROID,
            fcm_token="fcm-token-new",
        )
    )

    assert second.id == first.id
    assert second.installation_id == installation_id
    assert second.fcm_token == "fcm-token-new"

    with psycopg.connect(dsn) as connection:
        count = connection.execute(
            """
            SELECT COUNT(*)
            FROM nowave.devices
            WHERE installation_id = %s
            """,
            (installation_id,),
        ).fetchone()[0]

        token = connection.execute(
            """
            SELECT fcm_token
            FROM nowave.devices
            WHERE installation_id = %s
            """,
            (installation_id,),
        ).fetchone()[0]

    assert count == 1
    assert token == "fcm-token-new"


def test_installation_cannot_change_owner(
    dsn,
    monkeypatch,
):
    monkeypatch.setenv(
        "DATABASE_URL",
        dsn,
    )

    user_repository = PostgreSQLUserRepository()
    device_repository = PostgreSQLDeviceRepository()

    first_user = create_user()
    second_user = create_user()

    user_repository.save(first_user)
    user_repository.save(second_user)

    installation_id = uuid4()

    device_repository.register(
        Device(
            user_id=first_user.id,
            installation_id=installation_id,
            platform=DevicePlatform.ANDROID,
        )
    )

    with pytest.raises(
        DeviceConflictError,
        match="installation belongs to another user",
    ):
        device_repository.register(
            Device(
                user_id=second_user.id,
                installation_id=installation_id,
                platform=DevicePlatform.ANDROID,
            )
        )

    with psycopg.connect(dsn) as connection:
        owner_id = connection.execute(
            """
            SELECT user_id
            FROM nowave.devices
            WHERE installation_id = %s
            """,
            (installation_id,),
        ).fetchone()[0]

    assert owner_id == first_user.id


def test_fcm_token_cannot_belong_to_two_devices(
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

    device_repository.register(
        Device(
            user_id=user.id,
            installation_id=uuid4(),
            platform=DevicePlatform.ANDROID,
            fcm_token="same-fcm-token",
        )
    )

    with pytest.raises(
        DeviceConflictError,
        match="fcm token already assigned to another device",
    ):
        device_repository.register(
            Device(
                user_id=user.id,
                installation_id=uuid4(),
                platform=DevicePlatform.ANDROID,
                fcm_token="same-fcm-token",
            )
        )
