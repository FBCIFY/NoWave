from uuid import uuid4

import pytest

from app.domain.boat import Boat, BoatType


def test_create_boat():
    user_id = uuid4()

    boat = Boat(
        user_id=user_id,
        boat_type=BoatType.SAILBOAT,
        name="Ulysse",
        flag_country="FR",
    )

    assert boat.user_id == user_id
    assert boat.boat_type == BoatType.SAILBOAT
    assert boat.name == "Ulysse"
    assert boat.flag_country == "FR"
    assert boat.id is not None
    assert boat.created_at is not None
    assert boat.updated_at is not None


def test_create_boat_normalizes_values():
    boat = Boat(
        user_id=uuid4(),
        boat_type="voilier",
        name="  Ulysse  ",
        flag_country="fr",
    )

    assert boat.boat_type == BoatType.SAILBOAT
    assert boat.name == "Ulysse"
    assert boat.flag_country == "FR"


def test_create_boat_without_optional_fields():
    boat = Boat(
        user_id=uuid4(),
        boat_type=BoatType.MOTORBOAT,
    )

    assert boat.name is None
    assert boat.flag_country is None


def test_create_boat_requires_user():
    with pytest.raises(
        ValueError,
        match="user_id is required",
    ):
        Boat(
            user_id=None,
            boat_type=BoatType.SAILBOAT,
        )


def test_create_boat_rejects_invalid_type():
    with pytest.raises(
        ValueError,
        match="invalid boat type",
    ):
        Boat(
            user_id=uuid4(),
            boat_type="yacht",
        )


def test_create_boat_rejects_name_over_100_characters():
    with pytest.raises(
        ValueError,
        match="boat name cannot exceed 100 characters",
    ):
        Boat(
            user_id=uuid4(),
            boat_type=BoatType.SAILBOAT,
            name="A" * 101,
        )


def test_create_boat_rejects_invalid_flag_country():
    with pytest.raises(
        ValueError,
        match="flag_country must contain exactly 2 characters",
    ):
        Boat(
            user_id=uuid4(),
            boat_type=BoatType.SAILBOAT,
            flag_country="FRA",
        )


def test_update_boat_name():
    boat = Boat(
        user_id=uuid4(),
        boat_type=BoatType.SAILBOAT,
        name="Ulysse",
    )

    boat.update(
        {
            "name": "  NoWave  ",
        }
    )

    assert boat.name == "NoWave"
    assert boat.boat_type == BoatType.SAILBOAT


def test_update_boat_type():
    boat = Boat(
        user_id=uuid4(),
        boat_type=BoatType.SAILBOAT,
    )

    boat.update(
        {
            "boat_type": "catamaran",
        }
    )

    assert boat.boat_type == BoatType.CATAMARAN


def test_update_boat_flag_country():
    boat = Boat(
        user_id=uuid4(),
        boat_type=BoatType.SAILBOAT,
        flag_country="FR",
    )

    boat.update(
        {
            "flag_country": "it",
        }
    )

    assert boat.flag_country == "IT"


def test_update_can_clear_optional_fields():
    boat = Boat(
        user_id=uuid4(),
        boat_type=BoatType.SAILBOAT,
        name="Ulysse",
        flag_country="FR",
    )

    boat.update(
        {
            "name": None,
            "flag_country": None,
        }
    )

    assert boat.name is None
    assert boat.flag_country is None


def test_update_rejects_invalid_boat_type():
    boat = Boat(
        user_id=uuid4(),
        boat_type=BoatType.SAILBOAT,
    )

    with pytest.raises(
        ValueError,
        match="invalid boat type",
    ):
        boat.update(
            {
                "boat_type": "yacht",
            }
        )
