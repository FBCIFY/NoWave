from uuid import UUID

from app.application.ports.device_repository import (
    DeviceRepository,
)
from app.application.ports.user_repository import UserRepository
from app.domain.device import Device, DevicePlatform
from app.domain.errors import UserNotFoundError


class RegisterDevice:
    def __init__(
        self,
        user_repository: UserRepository,
        device_repository: DeviceRepository,
    ):
        self.user_repository = user_repository
        self.device_repository = device_repository

    def execute(
        self,
        firebase_uid: str,
        installation_id: UUID,
        platform: DevicePlatform,
        fcm_token: str | None = None,
    ) -> Device:
        user = self.user_repository.get_by_firebase_uid(
            firebase_uid
        )

        if user is None:
            raise UserNotFoundError(
                "user profile not found"
            )

        device = Device(
            user_id=user.id,
            installation_id=installation_id,
            platform=platform,
            fcm_token=fcm_token,
        )

        return self.device_repository.register(device)
