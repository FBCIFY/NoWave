from uuid import uuid4

import pytest

from app.application.services.deactivate_device import (
    DeactivateDevice,
)
from app.domain.errors import (
    DeviceNotFoundError,
    UserNotFoundError,
)
from app.domain.user import User


class FakeUserRepository:
    def __init__(self, user=None):
        self.user = user

    def get_by_firebase_uid(self, firebase_uid):
        return self.user


class FakeDeviceRepository:
    def __init__(self, result=True):
        self.result = result
        self.user_id = None
        self.installation_id = None

    def deactivate(
        self,
        user_id,
        installation_id,
    ):
        self.user_id = user_id
        self.installation_id = installation_id
        return self.result


def create_user():
    return User(
        firebase_uid="firebase-jonathan",
        username="jonathan",
        email="jonathan@example.com",
    )


def test_deactivate_device_success():
    user = create_user()
    installation_id = uuid4()

    device_repository = FakeDeviceRepository()

    service = DeactivateDevice(
        user_repository=FakeUserRepository(user),
        device_repository=device_repository,
    )

    service.execute(
        firebase_uid=user.firebase_uid,
        installation_id=installation_id,
    )

    assert device_repository.user_id == user.id
    assert (
        device_repository.installation_id
        == installation_id
    )


def test_deactivate_device_user_not_found():
    service = DeactivateDevice(
        user_repository=FakeUserRepository(None),
        device_repository=FakeDeviceRepository(),
    )

    with pytest.raises(UserNotFoundError):
        service.execute(
            firebase_uid="missing-user",
            installation_id=uuid4(),
        )


def test_deactivate_device_not_found():
    user = create_user()

    service = DeactivateDevice(
        user_repository=FakeUserRepository(user),
        device_repository=FakeDeviceRepository(
            result=False,
        ),
    )

    with pytest.raises(DeviceNotFoundError):
        service.execute(
            firebase_uid=user.firebase_uid,
            installation_id=uuid4(),
        )
