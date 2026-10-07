import pytest

from app.application.ports.auth_provider import AuthProvider
from app.application.ports.user_repository import UserRepository
from app.application.services.delete_user import DeleteUser
from app.domain.user import User


class FakeUserRepository(UserRepository):
    def __init__(self):
        self.users = []

    def get_by_firebase_uid(
        self,
        firebase_uid: str,
    ) -> User | None:
        for user in self.users:
            if user.firebase_uid == firebase_uid:
                return user

        return None

    def get_by_username(
        self,
        username: str,
    ) -> User | None:
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
        # Signature compatible avec NW-145.
        return user

    def delete(self, user: User) -> None:
        self.users.remove(user)


class FakeAuthProvider(AuthProvider):
    def __init__(self):
        self.deleted_uids = []
        self.delete_attempts = []
        self.fail_next_delete = False

    def delete_identity(
        self,
        firebase_uid: str,
    ) -> None:
        self.delete_attempts.append(
            firebase_uid
        )

        if self.fail_next_delete:
            self.fail_next_delete = False
            raise RuntimeError(
                "firebase unavailable"
            )

        self.deleted_uids.append(
            firebase_uid
        )


def make_user():
    return User(
        firebase_uid="firebase_123",
        username="Jonathan Cahoreau",
        email="jonathan@example.com",
    )


def test_delete_user_success():
    repository = FakeUserRepository()
    auth_provider = FakeAuthProvider()

    repository.save(make_user())

    service = DeleteUser(
        user_repository=repository,
        auth_provider=auth_provider,
    )

    service.execute(
        "firebase_123"
    )

    assert repository.users == []
    assert auth_provider.deleted_uids == [
        "firebase_123"
    ]


def test_delete_user_resumes_after_firebase_failure():
    repository = FakeUserRepository()
    auth_provider = FakeAuthProvider()

    repository.save(make_user())

    auth_provider.fail_next_delete = True

    service = DeleteUser(
        user_repository=repository,
        auth_provider=auth_provider,
    )

    with pytest.raises(
        RuntimeError,
        match="firebase unavailable",
    ):
        service.execute(
            "firebase_123"
        )

    # La partie SQL est déjà terminée.
    assert repository.users == []

    # La seconde tentative reprend côté Firebase.
    service.execute(
        "firebase_123"
    )

    assert auth_provider.delete_attempts == [
        "firebase_123",
        "firebase_123",
    ]

    assert auth_provider.deleted_uids == [
        "firebase_123"
    ]


def test_delete_user_without_sql_profile_still_deletes_identity():
    repository = FakeUserRepository()
    auth_provider = FakeAuthProvider()

    service = DeleteUser(
        user_repository=repository,
        auth_provider=auth_provider,
    )

    service.execute(
        "firebase_123"
    )

    assert repository.users == []

    assert auth_provider.deleted_uids == [
        "firebase_123"
    ]
