from fastapi import APIRouter, Depends, status

from app.api.dependencies.auth import get_current_identity
from app.api.schemas.boat import (
    BoatCreateRequest,
    BoatResponse,
    BoatUpdateRequest,
)
from app.application.services.create_boat import CreateBoat
from app.application.services.delete_boat import DeleteBoat
from app.application.services.get_boat import GetBoat
from app.application.services.update_boat import UpdateBoat
from app.infrastructure.repositories.postgresql_boat_repository import (
    PostgreSQLBoatRepository,
)
from app.infrastructure.repositories.postgresql_user_repository import (
    PostgreSQLUserRepository,
)


router = APIRouter(
    prefix="/users/me/boat",
    tags=["boats"],
)


def repositories():
    return (
        PostgreSQLUserRepository(),
        PostgreSQLBoatRepository(),
    )


@router.get(
    "",
    response_model=BoatResponse,
)
def get_my_boat(
    identity: dict = Depends(get_current_identity),
):
    user_repository, boat_repository = repositories()

    service = GetBoat(
        user_repository=user_repository,
        boat_repository=boat_repository,
    )

    return service.execute(
        firebase_uid=identity["uid"],
    )


@router.post(
    "",
    response_model=BoatResponse,
    status_code=status.HTTP_201_CREATED,
)
def create_my_boat(
    request: BoatCreateRequest,
    identity: dict = Depends(get_current_identity),
):
    user_repository, boat_repository = repositories()

    service = CreateBoat(
        user_repository=user_repository,
        boat_repository=boat_repository,
    )

    return service.execute(
        firebase_uid=identity["uid"],
        boat_type=request.boat_type,
        name=request.name,
        flag_country=request.flag_country,
    )


@router.patch(
    "",
    response_model=BoatResponse,
)
def update_my_boat(
    request: BoatUpdateRequest,
    identity: dict = Depends(get_current_identity),
):
    user_repository, boat_repository = repositories()

    service = UpdateBoat(
        user_repository=user_repository,
        boat_repository=boat_repository,
    )

    changes = request.model_dump(
        exclude_unset=True,
    )

    return service.execute(
        firebase_uid=identity["uid"],
        changes=changes,
    )


@router.delete(
    "",
    status_code=status.HTTP_204_NO_CONTENT,
)
def delete_my_boat(
    identity: dict = Depends(get_current_identity),
):
    user_repository, boat_repository = repositories()

    service = DeleteBoat(
        user_repository=user_repository,
        boat_repository=boat_repository,
    )

    service.execute(
        firebase_uid=identity["uid"],
    )
