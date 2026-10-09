import pytest

from app.application.services.delete_boat import DeleteBoat
from app.application.services.get_boat import GetBoat
from app.application.services.update_boat import UpdateBoat
from app.domain.boat import Boat, BoatType
from app.domain.errors import (
    BoatNotFoundError,
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

    def update(self, boat, *, fields):
        self.boat = boat
        return boat

    def delete(self, boat):
        if self.boat is boat:
            self.boat = None


def make_user():
    return User(
        firebase_uid="firebase-user",
        username="jonathan",
        email="jonathan@nowave.test",
    )


def test_get_boat_success():
    user = make_user()

    boat = Boat(
        user_id=user.id,
        boat_type=BoatType.SAILBOAT,
        name="Ulysse",
    )

    service = GetBoat(
        user_repository=FakeUserRepository(user),
        boat_repository=FakeBoatRepository(boat),
    )

    result = service.execute("firebase-user")

    assert result == boat


def test_get_boat_not_found():
    user = make_user()

    service = GetBoat(
        user_repository=FakeUserRepository(user),
        boat_repository=FakeBoatRepository(),
    )

    with pytest.raises(
        BoatNotFoundError,
        match="boat not found",
    ):
        service.execute("firebase-user")


def test_update_boat_success():
    user = make_user()

    boat = Boat(
        user_id=user.id,
        boat_type=BoatType.SAILBOAT,
        name="Ulysse",
        flag_country="FR",
    )

    repository = FakeBoatRepository(boat)

    service = UpdateBoat(
        user_repository=FakeUserRepository(user),
        boat_repository=repository,
    )

    updated = service.execute(
        firebase_uid="firebase-user",
        changes={
            "name": "NoWave",
            "boat_type": "catamaran",
            "flag_country": "it",
        },
    )

    assert updated.name == "NoWave"
    assert updated.boat_type == BoatType.CATAMARAN
    assert updated.flag_country == "IT"


def test_update_boat_not_found():
    user = make_user()

    service = UpdateBoat(
        user_repository=FakeUserRepository(user),
        boat_repository=FakeBoatRepository(),
    )

    with pytest.raises(
        BoatNotFoundError,
        match="boat not found",
    ):
        service.execute(
            firebase_uid="firebase-user",
            changes={"name": "NoWave"},
        )


def test_delete_boat_success():
    user = make_user()

    boat = Boat(
        user_id=user.id,
        boat_type=BoatType.SAILBOAT,
    )

    repository = FakeBoatRepository(boat)

    service = DeleteBoat(
        user_repository=FakeUserRepository(user),
        boat_repository=repository,
    )

    service.execute("firebase-user")

    assert repository.boat is None


def test_delete_boat_not_found():
    user = make_user()

    service = DeleteBoat(
        user_repository=FakeUserRepository(user),
        boat_repository=FakeBoatRepository(),
    )

    with pytest.raises(
        BoatNotFoundError,
        match="boat not found",
    ):
        service.execute("firebase-user")


def test_services_require_existing_user():
    user_repository = FakeUserRepository()
    boat_repository = FakeBoatRepository()

    get_service = GetBoat(
        user_repository,
        boat_repository,
    )

    delete_service = DeleteBoat(
        user_repository,
        boat_repository,
    )

    update_service = UpdateBoat(
        user_repository,
        boat_repository,
    )

    with pytest.raises(
        UserNotFoundError,
        match="user profile not found",
    ):
        get_service.execute("unknown-user")

    with pytest.raises(
        UserNotFoundError,
        match="user profile not found",
    ):
        delete_service.execute("unknown-user")

    with pytest.raises(
        UserNotFoundError,
        match="user profile not found",
    ):
        update_service.execute(
            firebase_uid="unknown-user",
            changes={"name": "NoWave"},
        )
