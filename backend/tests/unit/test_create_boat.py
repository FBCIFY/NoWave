from uuid import uuid4

import pytest

from app.application.services.create_boat import CreateBoat
from app.domain.boat import BoatType
from app.domain.errors import (
    BoatAlreadyExistsError,
    UserNotFoundError,
)
from app.domain.user import User


class FakeUserRepository:
    def __init__(self, user=None):
        self.user = user

    def get_by_firebase_uid(self, firebase_uid):
        if (
            self.user is not None
            and self.user.firebase_uid == firebase_uid
        ):
            return self.user

        return None


class FakeBoatRepository:
    def __init__(self, boat=None):
        self.boat = boat

    def get_by_user_id(self, user_id):
        if (
            self.boat is not None
            and self.boat.user_id == user_id
        ):
            return self.boat

        return None

    def save(self, boat):
        self.boat = boat
        return boat


def test_create_boat_success():
    user = User(
        firebase_uid="firebase-user",
        username="jonathan",
        email="jonathan@nowave.test",
    )

    boat_repository = FakeBoatRepository()

    service = CreateBoat(
        user_repository=FakeUserRepository(user),
        boat_repository=boat_repository,
    )

    boat = service.execute(
        firebase_uid="firebase-user",
        boat_type=BoatType.SAILBOAT,
        name="Ulysse",
        flag_country="fr",
    )

    assert boat.user_id == user.id
    assert boat.boat_type == BoatType.SAILBOAT
    assert boat.name == "Ulysse"
    assert boat.flag_country == "FR"

    assert boat_repository.boat == boat


def test_create_boat_requires_existing_user():
    service = CreateBoat(
        user_repository=FakeUserRepository(),
        boat_repository=FakeBoatRepository(),
    )

    with pytest.raises(
        UserNotFoundError,
        match="user profile not found",
    ):
        service.execute(
            firebase_uid="unknown-user",
            boat_type=BoatType.SAILBOAT,
        )


def test_create_boat_rejects_second_boat():
    user = User(
        firebase_uid="firebase-user",
        username="jonathan",
        email="jonathan@nowave.test",
    )

    from app.domain.boat import Boat

    existing_boat = Boat(
        user_id=user.id,
        boat_type=BoatType.SAILBOAT,
    )

    service = CreateBoat(
        user_repository=FakeUserRepository(user),
        boat_repository=FakeBoatRepository(existing_boat),
    )

    with pytest.raises(
        BoatAlreadyExistsError,
        match="boat already exists",
    ):
        service.execute(
            firebase_uid="firebase-user",
            boat_type=BoatType.CATAMARAN,
        )
