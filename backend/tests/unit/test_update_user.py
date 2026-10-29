from datetime import date

import pytest

from app.application.ports.user_repository import UserRepository
from app.application.services.update_user import UpdateUser
from app.domain.errors import (
    UserNotFoundError,
    UsernameAlreadyExistsError,
)
from app.domain.user import User


class FakeUserRepository(UserRepository):
    def __init__(self):
        self.users = []
        self.update_calls = 0

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

    def update(
        self,
        user: User,
        fields: set[str] | None = None,
    ) -> User:
        self.update_calls += 1
        return user

    def delete(self, user: User) -> None:
        self.users.remove(user)


def test_update_username_success():
    repository = FakeUserRepository()

    user = User(
        firebase_uid="firebase_123",
        username="Jonathan",
        email="jonathan@example.com",
    )

    repository.save(user)

    update_user = UpdateUser(repository)

    updated_user = update_user.execute(
        firebase_uid="firebase_123",
        changes={
            "username": "John",
        },
    )

    assert updated_user.username == "John"


def test_update_multiple_fields_success():
    repository = FakeUserRepository()

    user = User(
        firebase_uid="firebase_123",
        username="Jonathan",
        email="jonathan@example.com",
    )

    repository.save(user)

    update_user = UpdateUser(repository)

    updated_user = update_user.execute(
        firebase_uid="firebase_123",
        changes={
            "date_of_birth": date(1985, 1, 1),
            "nationality": "fr",
            "show_user_name": True,
            "show_boat_info": True,
            "notifications_enabled": True,
        },
    )

    assert updated_user.date_of_birth == date(1985, 1, 1)
    assert updated_user.nationality == "FR"
    assert updated_user.show_user_name is True
    assert updated_user.show_boat_info is True
    assert updated_user.notifications_enabled is True


def test_update_only_changes_provided_fields():
    repository = FakeUserRepository()

    user = User(
        firebase_uid="firebase_123",
        username="Jonathan",
        email="jonathan@example.com",
        nationality="FR",
    )

    repository.save(user)

    update_user = UpdateUser(repository)

    updated_user = update_user.execute(
        firebase_uid="firebase_123",
        changes={
            "show_user_name": True,
        },
    )

    assert updated_user.username == "Jonathan"
    assert updated_user.email == "jonathan@example.com"
    assert updated_user.nationality == "FR"
    assert updated_user.show_user_name is True


def test_update_with_no_changes_is_noop():
    repository = FakeUserRepository()

    user = User(
        firebase_uid="firebase_123",
        username="Jonathan",
        email="jonathan@example.com",
    )

    repository.save(user)

    update_user = UpdateUser(repository)

    updated_user = update_user.execute(
        firebase_uid="firebase_123",
        changes={},
    )

    assert updated_user is user
    assert repository.update_calls == 0


def test_update_user_not_found_raises_error():
    repository = FakeUserRepository()

    update_user = UpdateUser(repository)

    with pytest.raises(UserNotFoundError):
        update_user.execute(
            firebase_uid="unknown_uid",
            changes={
                "username": "John",
            },
        )


def test_update_username_already_exists_raises_error():
    repository = FakeUserRepository()

    user_1 = User(
        firebase_uid="firebase_123",
        username="Jonathan",
        email="jonathan@example.com",
    )

    user_2 = User(
        firebase_uid="firebase_456",
        username="Brice",
        email="brice@example.com",
    )

    repository.save(user_1)
    repository.save(user_2)

    update_user = UpdateUser(repository)

    with pytest.raises(UsernameAlreadyExistsError):
        update_user.execute(
            firebase_uid="firebase_123",
            changes={
                "username": "Brice",
            },
        )


def test_user_can_keep_same_username():
    repository = FakeUserRepository()

    user = User(
        firebase_uid="firebase_123",
        username="Jonathan",
        email="jonathan@example.com",
    )

    repository.save(user)

    update_user = UpdateUser(repository)

    updated_user = update_user.execute(
        firebase_uid="firebase_123",
        changes={
            "username": "Jonathan",
        },
    )

    assert updated_user.username == "Jonathan"
