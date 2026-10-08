from abc import ABC, abstractmethod
from uuid import UUID

from app.domain.device import Device
from app.domain.device_position import DevicePosition


class DeviceRepository(ABC):
    @abstractmethod
    def register(self, device: Device) -> Device:
        pass

    @abstractmethod
    def get_active_by_user_and_installation(
        self,
        user_id: UUID,
        installation_id: UUID,
    ) -> Device | None:
        pass

    @abstractmethod
    def save_position(
        self,
        position: DevicePosition,
    ) -> DevicePosition | None:
        """Save atomically with the activity check and presence update.

        Raise DeviceNotFoundError if the device is absent or inactive.
        Return None only when the measurement is older than the stored one.
        """
        pass

    @abstractmethod
    def deactivate(
        self,
        user_id: UUID,
        installation_id: UUID,
    ) -> bool:
        pass
