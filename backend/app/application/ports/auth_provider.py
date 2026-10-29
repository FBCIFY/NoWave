from abc import ABC, abstractmethod


class AuthProvider(ABC):
    @abstractmethod
    def delete_identity(self, firebase_uid: str) -> None:
        pass
