import pytest

from app.domain.boat import Boat, BoatType
from app.domain.errors import BoatAlreadyExistsError
from app.domain.user import User
from app.infrastructure.repositories.postgresql_boat_repository import (
    PostgreSQLBoatRepository,
)
from app.infrastructure.repositories.postgresql_user_repository import (
    PostgreSQLUserRepository,
)


def test_boat_repository_crud(dsn, monkeypatch):
    monkeypatch.setenv("DATABASE_URL", dsn)

    user_repository = PostgreSQLUserRepository()
    boat_repository = PostgreSQLBoatRepository()

    user = User(
        firebase_uid="firebase-boat-repository-test",
        username="boat-repository-user",
        email="boat-repository-user@nowave.test",
    )

    user_repository.save(user)

    boat = Boat(
        user_id=user.id,
        boat_type=BoatType.SAILBOAT,
        name="Ulysse",
        flag_country="fr",
    )

    # CREATE
    boat_repository.save(boat)

    # READ
    found = boat_repository.get_by_user_id(user.id)

    assert found is not None
    assert found.id == boat.id
    assert found.user_id == user.id
    assert found.name == "Ulysse"
    assert found.boat_type == BoatType.SAILBOAT
    assert found.flag_country == "FR"

    # UPDATE
    boat.update(
        {
            "name": "NoWave",
            "boat_type": "catamaran",
            "flag_country": "it",
        }
    )

    boat_repository.update(boat)

    updated = boat_repository.get_by_user_id(user.id)

    assert updated is not None
    assert updated.name == "NoWave"
    assert updated.boat_type == BoatType.CATAMARAN
    assert updated.flag_country == "IT"

    # DELETE
    boat_repository.delete(boat)

    deleted = boat_repository.get_by_user_id(user.id)

    assert deleted is None


def test_boat_repository_rejects_second_boat(
    dsn,
    monkeypatch,
):
    monkeypatch.setenv(
        "DATABASE_URL",
        dsn,
    )

    user_repository = PostgreSQLUserRepository()
    boat_repository = PostgreSQLBoatRepository()

    user = User(
        firebase_uid="firebase-boat-conflict-test",
        username="boat-conflict-user",
        email="boat-conflict-user@nowave.test",
    )

    user_repository.save(user)

    first_boat = Boat(
        user_id=user.id,
        boat_type=BoatType.SAILBOAT,
    )

    second_boat = Boat(
        user_id=user.id,
        boat_type=BoatType.CATAMARAN,
    )

    boat_repository.save(first_boat)

    with pytest.raises(
        BoatAlreadyExistsError,
        match="boat already exists",
    ):
        boat_repository.save(second_boat)

    stored_boat = boat_repository.get_by_user_id(
        user.id
    )

    assert stored_boat is not None
    assert stored_boat.id == first_boat.id
    assert (
        stored_boat.boat_type
        == BoatType.SAILBOAT
    )
