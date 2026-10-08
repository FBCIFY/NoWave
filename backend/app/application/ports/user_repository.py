from abc import ABC, abstractmethod

from app.domain.user import User


class UserRepository(ABC):
    @abstractmethod
    def get_by_firebase_uid(self, firebase_uid: str) -> User | None:
        pass

    @abstractmethod
    def get_by_username(self, username: str) -> User | None:
        pass

    @abstractmethod
    def save(self, user: User) -> User:
        pass

    @abstractmethod
    def update(
        self,
        user: User,
        fields: set[str] | None = None,
    ) -> User:
        pass

    @abstractmethod
    def delete(self, user: User) -> None:
        pass
