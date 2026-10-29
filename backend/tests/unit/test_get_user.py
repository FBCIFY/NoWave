import pytest

from app.application.ports.user_repository import UserRepository
from app.application.services.get_user import GetUser
from app.domain.errors import UserNotFoundError
from app.domain.user import User


class FakeUserRepository(UserRepository):
    def __init__(self):
        self.users = []

    def get_by_firebase_uid(self, firebase_uid: str) -> User | None:
        for user in self.users:
            if user.firebase_uid == firebase_uid:
                return user

        return None

    def get_by_username(self, username: str) -> User | None:
        for user in self.users:
            if user.username == username:
                return user

        return None

    def save(self, user: User) -> User:
        self.users.append(user)
        return user

    def update(self, user: User) -> User:
        return user

    def delete(self, user: User) -> None:
        self.users.remove(user)


def test_get_user_success():
    repository = FakeUserRepository()

    existing_user = User(
        firebase_uid="firebase_123",
        username="Jonathan",
        email="jonathan@example.com",
    )

    repository.save(existing_user)

    get_user = GetUser(repository)

    user = get_user.execute("firebase_123")

    assert user == existing_user
    assert user.username == "Jonathan"


def test_get_user_not_found_raises_error():
    repository = FakeUserRepository()
    get_user = GetUser(repository)

    with pytest.raises(UserNotFoundError):
        get_user.execute("unknown_firebase_uid")
