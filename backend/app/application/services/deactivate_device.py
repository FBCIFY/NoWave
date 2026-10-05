from uuid import UUID

from app.application.ports.device_repository import (
    DeviceRepository,
)
from app.application.ports.user_repository import UserRepository
from app.domain.errors import (
    DeviceNotFoundError,
    UserNotFoundError,
)


class DeactivateDevice:
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
    ) -> None:
        user = self.user_repository.get_by_firebase_uid(
            firebase_uid
        )

        if user is None:
            raise UserNotFoundError(
                "user profile not found"
            )

        deactivated = self.device_repository.deactivate(
            user_id=user.id,
            installation_id=installation_id,
        )

        if not deactivated:
            raise DeviceNotFoundError(
                "device not found"
            )
