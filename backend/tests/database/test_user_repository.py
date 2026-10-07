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

