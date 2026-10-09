from abc import ABC, abstractmethod
from uuid import UUID

from app.domain.boat import Boat


class BoatRepository(ABC):
    @abstractmethod
    def get_by_user_id(self, user_id: UUID) -> Boat | None:
        pass

    @abstractmethod
    def save(self, boat: Boat) -> Boat:
        pass

    @abstractmethod
    def update(self, boat: Boat, *, fields: set[str]) -> Boat:
        """Update only supplied fields and return the stored boat."""
        pass

    @abstractmethod
    def delete(self, boat: Boat) -> None:
        pass
