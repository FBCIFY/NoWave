from uuid import uuid4

import pytest
from psycopg.errors import UniqueViolation

from app.domain.errors import (
    EmailAlreadyRegisteredError,
    UserAlreadyExistsError,
    UserNotFoundError,
    UsernameAlreadyExistsError,
)
from app.domain.user import User
from app.infrastructure.repositories.postgresql_user_repository import (
    PostgreSQLUserRepository,
)


def test_user_repository_crud(dsn, monkeypatch):
    monkeypatch.setenv("DATABASE_URL", dsn)

    repository = PostgreSQLUserRepository()

    user = User(
        firebase_uid="firebase-repository-test",
        username="repository-user",
        email="repository-user@nowave.test",
    )

    # CREATE
    repository.save(user)

    # READ BY FIREBASE UID
    found_by_uid = repository.get_by_firebase_uid(
        "firebase-repository-test"
    )

    assert found_by_uid is not None
    assert found_by_uid.id == user.id
    assert found_by_uid.firebase_uid == user.firebase_uid
    assert found_by_uid.username == user.username
    assert found_by_uid.email == user.email

    # READ BY USERNAME
    found_by_username = repository.get_by_username(
        "repository-user"
    )

    assert found_by_username is not None
    assert found_by_username.id == user.id

    # UPDATE
    user.update_profile(
        {
            "username": "repository-user-updated",
            "nationality": "fr",
            "show_user_name": True,
        }
    )

    repository.update(user)

    updated = repository.get_by_firebase_uid(
        "firebase-repository-test"
    )

    assert updated is not None
    assert updated.username == "repository-user-updated"
    assert updated.nationality == "FR"
    assert updated.show_user_name is True

    # DELETE
    repository.delete(user)

    deleted = repository.get_by_firebase_uid(
        "firebase-repository-test"
    )

    assert deleted is None


def test_partial_updates_preserve_omitted_consent(
    dsn,
    monkeypatch,
):
    monkeypatch.setenv("DATABASE_URL", dsn)

    repository = PostgreSQLUserRepository()

    user = User(
        firebase_uid="firebase-partial-update-test",
        username="Initial User",
        email="partial-update@nowave.test",
        nationality="FR",
        show_user_name=True,
    )

    repository.save(user)

    consent_snapshot = repository.get_by_firebase_uid(
        "firebase-partial-update-test"
    )
    profile_snapshot = repository.get_by_firebase_uid(
        "firebase-partial-update-test"
    )

    assert consent_snapshot is not None
    assert profile_snapshot is not None

    consent_snapshot.update_profile(
        {
            "show_user_name": False,
        }
    )

    repository.update(
        consent_snapshot,
        fields={"show_user_name"},
    )

    profile_snapshot.update_profile(
        {
            "username": "Updated User",
        }
    )

    repository.update(
        profile_snapshot,
        fields={"username"},
    )

    updated = repository.get_by_firebase_uid(
        "firebase-partial-update-test"
    )

    assert updated is not None
    assert updated.username == "Updated User"
    assert updated.show_user_name is False

    repository.delete(updated)


def test_update_raises_when_user_disappears(
    dsn,
    monkeypatch,
):
    monkeypatch.setenv("DATABASE_URL", dsn)

    repository = PostgreSQLUserRepository()

    user = User(
        firebase_uid="firebase-update-race-test",
        username="race-user",
        email="race-user@nowave.test",
    )

    repository.save(user)

    snapshot = repository.get_by_firebase_uid(
        "firebase-update-race-test"
    )
    assert snapshot is not None

    repository.delete(snapshot)

    snapshot.update_profile({"username": "race-user-updated"})

    with pytest.raises(
        UserNotFoundError,
        match="user profile not found",
    ):
        repository.update(
            snapshot,
            fields={"username"},
        )


def test_unrelated_unique_violation_is_not_translated(dsn, monkeypatch):
    monkeypatch.setenv("DATABASE_URL", dsn)
    repository = PostgreSQLUserRepository()
    suffix = uuid4().hex
    first = User(
        firebase_uid=f"first-{suffix}",
        username=f"first-{suffix}",
        email=f"first-{suffix}@nowave.test",
    )
    repository.save(first)
    duplicate_id = User(
        id=first.id,
        firebase_uid=f"second-{suffix}",
        username=f"second-{suffix}",
        email=f"second-{suffix}@nowave.test",
    )
    with pytest.raises(UniqueViolation) as failure:
        repository.save(duplicate_id)
    assert failure.value.diag.constraint_name == "users_pkey"
    assert repository.get_by_firebase_uid(duplicate_id.firebase_uid) is None


@pytest.mark.parametrize(
    ("field", "expected_error"),
    [
        ("username", UsernameAlreadyExistsError),
        ("firebase_uid", UserAlreadyExistsError),
        ("email", EmailAlreadyRegisteredError),
    ],
)
def test_save_translates_user_unique_conflicts(
    dsn, monkeypatch, field, expected_error
):
    monkeypatch.setenv("DATABASE_URL", dsn)
    repository = PostgreSQLUserRepository()
    suffix = uuid4().hex
    first = User(
        firebase_uid=f"first-{suffix}",
        username=f"first-{suffix}",
        email=f"first-{suffix}@nowave.test",
    )
    second = User(
        firebase_uid=f"second-{suffix}",
        username=f"second-{suffix}",
        email=f"second-{suffix}@nowave.test",
    )
    repository.save(first)
    setattr(second, field, getattr(first, field))

    with pytest.raises(expected_error):
        repository.save(second)


def test_update_translates_username_unique_conflict(dsn, monkeypatch):
    monkeypatch.setenv("DATABASE_URL", dsn)
    repository = PostgreSQLUserRepository()
    suffix = uuid4().hex
    first = User(
        firebase_uid=f"first-update-{suffix}",
        username=f"first-update-{suffix}",
        email=f"first-update-{suffix}@nowave.test",
    )
    second = User(
        firebase_uid=f"second-update-{suffix}",
        username=f"second-update-{suffix}",
        email=f"second-update-{suffix}@nowave.test",
    )
    repository.save(first)
    repository.save(second)
    original_username = second.username
    second.update_profile({"username": first.username})

    with pytest.raises(UsernameAlreadyExistsError):
        repository.update(second, fields={"username"})

    persisted = repository.get_by_firebase_uid(second.firebase_uid)
    assert persisted is not None
    assert persisted.username == original_username
