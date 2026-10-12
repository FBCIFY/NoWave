from fastapi import APIRouter, Depends, Query, status

from app.api.dependencies.auth import (
    reuse_current_user,
    get_authenticated_identity,
    get_current_identity,
)
from app.api.schemas.admin import PaginatedResponse
from app.api.schemas.alert import AlertResponse
from app.api.schemas.report import GeoJSONPoint
from app.api.schemas.user import UserCreateRequest, UserProfileResponse, UserUpdateRequest
from app.application.services.create_user import CreateUser
from app.application.services.get_user import GetUser
from app.application.services.list_my_alerts import ListMyAlerts
from app.application.services.update_user import UpdateUser
from app.application.services.delete_user import DeleteUser
from app.domain.alert import Alert
from app.domain.pagination import (
    DEFAULT_PAGE_LIMIT,
    MAX_PAGE,
    MAX_PAGE_LIMIT,
)
from app.infrastructure.adapters.firebase_auth_adapter import FirebaseAuthAdapter
from app.infrastructure.repositories.postgresql_alert_history_repository import (
    PostgreSQLAlertHistoryRepository,
)
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
    repository = reuse_current_user(identity, PostgreSQLUserRepository())
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


@router.get(
    "/me/alerts",
    response_model=PaginatedResponse[AlertResponse],
)
def list_my_alerts(
    page: int = Query(default=1, ge=1, le=MAX_PAGE),
    limit: int = Query(
        default=DEFAULT_PAGE_LIMIT,
        ge=1,
        le=MAX_PAGE_LIMIT,
    ),
    identity: dict = Depends(get_current_identity),
):
    service = ListMyAlerts(
        user_repository=PostgreSQLUserRepository(),
        alert_history_repository=PostgreSQLAlertHistoryRepository(),
    )

    alerts = service.execute(
        firebase_uid=identity["uid"],
        page=page,
        limit=limit,
    )

    return PaginatedResponse(
        items=[
            alert_response(alert)
            for alert in alerts.items
        ],
        page=alerts.page,
        limit=alerts.limit,
        total=alerts.total,
        pages=alerts.pages,
    )


def alert_response(
    alert: Alert,
) -> AlertResponse:
    return AlertResponse(
        id=alert.id,
        report_id=alert.report_id,
        report_version=alert.report_version,
        category=alert.category,
        position=GeoJSONPoint(
            type="Point",
            coordinates=[
                alert.longitude,
                alert.latitude,
            ],
        ),
        distance_m=alert.distance_m,
        alerted_at=alert.alerted_at,
    )
