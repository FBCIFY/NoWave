import pytest

from app.application.ports.user_repository import UserRepository
from app.application.services.create_user import CreateUser
from app.domain.errors import (
    EmailNotVerifiedError,
    UserAlreadyExistsError,
    UsernameAlreadyExistsError,
)
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


def test_create_user_success():
    repository = FakeUserRepository()
    create_user = CreateUser(repository)

    user = create_user.execute(
        firebase_uid="firebase_123",
        username="Jonathan",
        email="jonathan@example.com",
        email_verified=True,
    )

    assert user.firebase_uid == "firebase_123"
    assert user.username == "Jonathan"
    assert user.email == "jonathan@example.com"

    assert len(repository.users) == 1
    assert repository.users[0] == user


def test_create_user_with_unverified_email_raises_error():
    repository = FakeUserRepository()
    create_user = CreateUser(repository)

    with pytest.raises(EmailNotVerifiedError):
        create_user.execute(
            firebase_uid="firebase_123",
            username="Jonathan",
            email="jonathan@example.com",
            email_verified=False,
        )

    assert len(repository.users) == 0


def test_create_user_when_profile_already_exists_raises_error():
    repository = FakeUserRepository()

    existing_user = User(
        firebase_uid="firebase_123",
        username="ExistingUser",
        email="existing@example.com",
    )

    repository.save(existing_user)

    create_user = CreateUser(repository)

    with pytest.raises(UserAlreadyExistsError):
        create_user.execute(
            firebase_uid="firebase_123",
            username="Jonathan",
            email="jonathan@example.com",
            email_verified=True,
        )

    assert len(repository.users) == 1


def test_create_user_when_username_already_exists_raises_error():
    repository = FakeUserRepository()

    existing_user = User(
        firebase_uid="firebase_existing",
        username="Jonathan",
        email="existing@example.com",
    )

    repository.save(existing_user)

    create_user = CreateUser(repository)

    with pytest.raises(UsernameAlreadyExistsError):
        create_user.execute(
            firebase_uid="firebase_new",
            username="Jonathan",
            email="jonathan@example.com",
            email_verified=True,
        )

    assert len(repository.users) == 1
