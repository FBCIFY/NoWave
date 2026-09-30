import pytest
from pydantic import ValidationError

from app.api.schemas.user import (
    UserCreateRequest,
    UserProfileResponse,
    UserUpdateRequest,
)
from app.domain.user import User


def test_create_user_request():
    request = UserCreateRequest(username="Jonathan")

    assert request.username == "Jonathan"


def test_create_user_request_trims_username():
    request = UserCreateRequest(username="  Jonathan  ")

    assert request.username == "Jonathan"


def test_create_user_request_rejects_empty_username():
    with pytest.raises(ValidationError):
        UserCreateRequest(username="   ")


def test_create_user_request_rejects_unknown_field():
    with pytest.raises(ValidationError):
        UserCreateRequest(
            username="Jonathan",
            role="admin",
        )


def test_update_user_request_is_partial():
    request = UserUpdateRequest(
        show_user_name=True,
    )

    assert request.show_user_name is True


def test_update_user_request_uppercases_nationality():
    request = UserUpdateRequest(
        nationality="fr",
    )

    assert request.nationality == "FR"


def test_update_user_request_allows_null_nationality():
    request = UserUpdateRequest(
        nationality=None,
    )

    assert request.nationality is None


def test_update_user_request_rejects_null_username():
    with pytest.raises(ValidationError):
        UserUpdateRequest(
            username=None,
        )


def test_update_user_request_rejects_unknown_field():
    with pytest.raises(ValidationError):
        UserUpdateRequest(
            email="user@nowave.test",
        )


def test_user_profile_response_from_user():
    user = User(
        firebase_uid="firebase-user-123",
        username="Jonathan",
        email="jonathan@nowave.test",
        nationality="fr",
    )

    response = UserProfileResponse.model_validate(user)

    assert response.id == user.id
    assert response.username == "Jonathan"
    assert response.nationality == "FR"
    assert response.role == user.role
    assert response.status == user.status


def test_user_profile_response_does_not_expose_private_identity():
    user = User(
        firebase_uid="firebase-user-123",
        username="Jonathan",
        email="jonathan@nowave.test",
    )

    response = UserProfileResponse.model_validate(user)
    data = response.model_dump()

    assert "firebase_uid" not in data
    assert "email" not in data
