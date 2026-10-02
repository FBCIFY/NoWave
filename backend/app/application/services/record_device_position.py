from datetime import datetime
from uuid import UUID

from app.application.ports.device_repository import (
    DeviceRepository,
)
from app.application.ports.user_repository import UserRepository
from app.domain.device_position import DevicePosition
from app.domain.errors import (
    DeviceNotFoundError,
    DevicePositionStaleError,
    UserNotFoundError,
)


class RecordDevicePosition:
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
        longitude: float,
        latitude: float,
        accuracy_m: float,
        measured_at: datetime,
        heading_deg: float | None = None,
    ) -> DevicePosition:
        user = self.user_repository.get_by_firebase_uid(
            firebase_uid
        )

        if user is None:
            raise UserNotFoundError(
                "user profile not found"
            )

        device = (
            self.device_repository
            .get_active_by_user_and_installation(
                user_id=user.id,
                installation_id=installation_id,
            )
        )

        if device is None:
            raise DeviceNotFoundError(
                "active device not found"
            )

        position = DevicePosition(
            device_id=device.id,
            longitude=longitude,
            latitude=latitude,
            accuracy_m=accuracy_m,
            heading_deg=heading_deg,
            measured_at=measured_at,
        )

        saved_position = (
            self.device_repository.save_position(
                position
            )
        )

        if saved_position is None:
            raise DevicePositionStaleError(
                "position measurement is not newer "
                "than the stored position"
            )

        return saved_position
