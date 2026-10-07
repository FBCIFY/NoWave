from fastapi import APIRouter, Depends, status

from app.api.dependencies.auth import (
    get_authenticated_identity,
    get_current_identity,
)
from app.api.schemas.user import UserCreateRequest, UserProfileResponse, UserUpdateRequest
from app.application.services.create_user import CreateUser
from app.application.services.get_user import GetUser
from app.application.services.update_user import UpdateUser
from app.application.services.delete_user import DeleteUser
from app.infrastructure.adapters.firebase_auth_adapter import FirebaseAuthAdapter
from app.infrastructure.repositories.postgresql_user_repository import (
    PostgreSQLUserRepository,
)


router = APIRouter(
    prefix="/users",
    tags=["users"],
)


@router.post(
    "/me",
    response_model=UserProfileResponse,
    status_code=status.HTTP_201_CREATED,
)
def create_my_profile(
    request: UserCreateRequest,
    identity: dict = Depends(get_authenticated_identity),
):
    repository = PostgreSQLUserRepository()
    create_user = CreateUser(repository)

    user = create_user.execute(
        firebase_uid=identity["uid"],
        username=request.username,
        email=identity.get("email", ""),
        email_verified=identity.get("email_verified", False),
    )

    return user


@router.get(
    "/me",
    response_model=UserProfileResponse,
)
def get_my_profile(
    identity: dict = Depends(get_authenticated_identity),
):
    repository = PostgreSQLUserRepository()
    get_user = GetUser(repository)

    user = get_user.execute(
        identity["uid"]
    )

    return user


@router.patch(
    "/me",
    response_model=UserProfileResponse,
)
def update_my_profile(
    request: UserUpdateRequest,
    identity: dict = Depends(get_current_identity),
):
    repository = PostgreSQLUserRepository()
    update_user = UpdateUser(repository)

    changes = request.model_dump(
        exclude_unset=True,
    )

    user = update_user.execute(
        firebase_uid=identity["uid"],
        changes=changes,
    )

    return user


@router.delete(
    "/me",
    status_code=status.HTTP_204_NO_CONTENT,
)
def delete_my_profile(
    identity: dict = Depends(get_authenticated_identity),
):
    repository = PostgreSQLUserRepository()
    auth_provider = FirebaseAuthAdapter()

    delete_user = DeleteUser(
        user_repository=repository,
        auth_provider=auth_provider,
    )

    delete_user.execute(
        identity["uid"]
    )
