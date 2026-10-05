from datetime import UTC, datetime, timedelta
from uuid import uuid4

import pytest

from app.domain.errors import GpsPrecisionInsufficientError

from app.application.services.record_device_position import (
    RecordDevicePosition,
)
from app.domain.device import Device, DevicePlatform
from app.domain.device_position import DevicePosition
from app.domain.errors import (
    DeviceNotFoundError,
    DevicePositionStaleError,
    UserNotFoundError,
)
from app.domain.user import User


class FakeUserRepository:
    def __init__(self, user=None):
        self.user = user

    def get_by_firebase_uid(self, firebase_uid):
        return self.user


class FakeDeviceRepository:
    def __init__(self, device=None):
        self.device = device
        self.saved_position = None
        self.return_stale = False

    def get_active_by_user_and_installation(
        self,
        user_id,
        installation_id,
    ):
        if self.device is None:
            return None

        if (
            self.device.user_id == user_id
            and self.device.installation_id == installation_id
            and self.device.is_active
        ):
            return self.device

        return None

    def save_position(self, position):
        if self.return_stale:
            return None

        self.saved_position = position
        return position


def create_user():
    return User(
        firebase_uid="firebase-jonathan",
        username="jonathan",
        email="jonathan@example.com",
    )


def create_device(user):
    return Device(
        user_id=user.id,
        installation_id=uuid4(),
        platform=DevicePlatform.ANDROID,
    )


def test_record_device_position_success():
    user = create_user()
    device = create_device(user)

    user_repository = FakeUserRepository(user)
    device_repository = FakeDeviceRepository(device)

    service = RecordDevicePosition(
        user_repository=user_repository,
        device_repository=device_repository,
    )

    measured_at = datetime.now(UTC)

    result = service.execute(
        firebase_uid=user.firebase_uid,
        installation_id=device.installation_id,
        longitude=5.37,
        latitude=43.29,
        accuracy_m=18.0,
        heading_deg=90.0,
        measured_at=measured_at,
    )

    assert result.device_id == device.id
    assert result.longitude == 5.37
    assert result.latitude == 43.29
    assert result.accuracy_m == 18.0
    assert result.heading_deg == 90.0
    assert result.measured_at == measured_at


def test_record_device_position_user_not_found():
    service = RecordDevicePosition(
        user_repository=FakeUserRepository(None),
        device_repository=FakeDeviceRepository(),
    )

    with pytest.raises(UserNotFoundError):
        service.execute(
            firebase_uid="missing-user",
            installation_id=uuid4(),
            longitude=5.37,
            latitude=43.29,
            accuracy_m=18.0,
            heading_deg=90.0,
            measured_at=datetime.now(UTC),
        )


def test_record_device_position_device_not_found():
    user = create_user()

    service = RecordDevicePosition(
        user_repository=FakeUserRepository(user),
        device_repository=FakeDeviceRepository(None),
    )

    with pytest.raises(DeviceNotFoundError):
        service.execute(
            firebase_uid=user.firebase_uid,
            installation_id=uuid4(),
            longitude=5.37,
            latitude=43.29,
            accuracy_m=18.0,
            heading_deg=90.0,
            measured_at=datetime.now(UTC),
        )


def test_record_device_position_rejects_old_measurement():
    user = create_user()
    device = create_device(user)

    device_repository = FakeDeviceRepository(device)
    device_repository.return_stale = True

    service = RecordDevicePosition(
        user_repository=FakeUserRepository(user),
        device_repository=device_repository,
    )

    with pytest.raises(DevicePositionStaleError):
        service.execute(
            firebase_uid=user.firebase_uid,
            installation_id=device.installation_id,
            longitude=5.37,
            latitude=43.29,
            accuracy_m=18.0,
            heading_deg=90.0,
            measured_at=datetime.now(UTC) - timedelta(minutes=1),
        )


def test_record_device_position_rejects_bad_accuracy():
    user = create_user()
    device = create_device(user)

    service = RecordDevicePosition(
        user_repository=FakeUserRepository(user),
        device_repository=FakeDeviceRepository(device),
    )

    with pytest.raises(GpsPrecisionInsufficientError):
        service.execute(
            firebase_uid=user.firebase_uid,
            installation_id=device.installation_id,
            longitude=5.37,
            latitude=43.29,
            accuracy_m=75.0,
            heading_deg=90.0,
            measured_at=datetime.now(UTC),
        )
