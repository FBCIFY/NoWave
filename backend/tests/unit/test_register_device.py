import pytest

from app.application.services.register_device import RegisterDevice
from app.domain.device import DevicePlatform
from app.domain.errors import UserNotFoundError
from app.domain.user import User


class FakeUserRepository:
    def __init__(self, user=None):
        self.user = user

    def get_by_firebase_uid(self, firebase_uid):
        if (
            self.user is not None
            and self.user.firebase_uid == firebase_uid
        ):
            return self.user

        return None


class FakeDeviceRepository:
    def __init__(self):
        self.device = None

    def register(self, device):
        self.device = device
        return device


def test_register_device_success():
    user = User(
        firebase_uid="firebase-user",
        username="jonathan",
        email="jonathan@nowave.test",
    )

    device_repository = FakeDeviceRepository()

    service = RegisterDevice(
        user_repository=FakeUserRepository(user),
        device_repository=device_repository,
    )

    device = service.execute(
        firebase_uid="firebase-user",
        installation_id="9d3f6a2e-7237-4dab-9fe9-054b4670d425",
        platform=DevicePlatform.ANDROID,
        fcm_token="test-fcm-token",
    )

    assert device.user_id == user.id
    assert (
        str(device.installation_id)
        == "9d3f6a2e-7237-4dab-9fe9-054b4670d425"
    )
    assert device.platform == DevicePlatform.ANDROID
    assert device.fcm_token == "test-fcm-token"
    assert device.is_active is True
    assert device_repository.device == device


def test_register_device_requires_user_profile():
    service = RegisterDevice(
        user_repository=FakeUserRepository(),
        device_repository=FakeDeviceRepository(),
    )

    with pytest.raises(
        UserNotFoundError,
        match="user profile not found",
    ):
        service.execute(
            firebase_uid="unknown-user",
            installation_id="9d3f6a2e-7237-4dab-9fe9-054b4670d425",
            platform=DevicePlatform.ANDROID,
        )
