from datetime import datetime
from uuid import UUID

import pytest

from app.domain.errors import (
    InvalidEmailError,
    InvalidFirebaseUidError,
    InvalidNationalityError,
    InvalidUsernameError,
)
from app.domain.user import User, UserRole, UserStatus


def test_create_user():
    user = User(
        firebase_uid="firebase_123",
        username="Jonathan",
        email="jonathan@example.com",
    )

    assert isinstance(user.id, UUID)

    assert user.firebase_uid == "firebase_123"
    assert user.username == "Jonathan"
    assert user.email == "jonathan@example.com"

    assert user.date_of_birth is None
    assert user.nationality is None

    assert user.role == UserRole.USER
    assert user.status == UserStatus.ACTIVE

    assert user.show_user_name is False
    assert user.show_boat_info is False
    assert user.notifications_enabled is False

    assert isinstance(user.created_at, datetime)
    assert isinstance(user.updated_at, datetime)


def test_username_is_trimmed():
    user = User(
        firebase_uid="firebase_123",
        username="  Jonathan  ",
        email="jonathan@example.com",
    )

    assert user.username == "Jonathan"


def test_username_with_internal_spaces_is_allowed():
    user = User(
        firebase_uid="firebase_123",
        username="Jonathan Cahoreau",
        email="jonathan@example.com",
    )

    assert user.username == "Jonathan Cahoreau"


def test_firebase_uid_is_trimmed():
    user = User(
        firebase_uid="  firebase_123  ",
        username="Jonathan",
        email="jonathan@example.com",
    )

    assert user.firebase_uid == "firebase_123"


def test_email_is_trimmed():
    user = User(
        firebase_uid="firebase_123",
        username="Jonathan",
        email="  jonathan@example.com  ",
    )

    assert user.email == "jonathan@example.com"


def test_nationality_is_uppercase():
    user = User(
        firebase_uid="firebase_123",
        username="Jonathan",
        email="jonathan@example.com",
        nationality="fr",
    )

    assert user.nationality == "FR"


def test_empty_firebase_uid_raises_error():
    with pytest.raises(InvalidFirebaseUidError):
        User(
            firebase_uid="",
            username="Jonathan",
            email="jonathan@example.com",
        )


def test_empty_username_raises_error():
    with pytest.raises(InvalidUsernameError):
        User(
            firebase_uid="firebase_123",
            username="",
            email="jonathan@example.com",
        )


def test_username_with_only_spaces_raises_error():
    with pytest.raises(InvalidUsernameError):
        User(
            firebase_uid="firebase_123",
            username="   ",
            email="jonathan@example.com",
        )


def test_username_longer_than_100_characters_raises_error():
    username = "a" * 101

    with pytest.raises(InvalidUsernameError):
        User(
            firebase_uid="firebase_123",
            username=username,
            email="jonathan@example.com",
        )


def test_empty_email_raises_error():
    with pytest.raises(InvalidEmailError):
        User(
            firebase_uid="firebase_123",
            username="Jonathan",
            email="",
        )


def test_email_longer_than_254_characters_raises_error():
    email = "a" * 255

    with pytest.raises(InvalidEmailError):
        User(
            firebase_uid="firebase_123",
            username="Jonathan",
            email=email,
        )


def test_invalid_nationality_raises_error():
    with pytest.raises(InvalidNationalityError):
        User(
            firebase_uid="firebase_123",
            username="Jonathan",
            email="jonathan@example.com",
            nationality="FRA",
        )
