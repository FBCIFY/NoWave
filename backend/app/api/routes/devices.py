from uuid import UUID

from fastapi import APIRouter, Depends, Header, Response, status

from app.api.dependencies.auth import (
    get_authenticated_identity,
    get_current_identity,
)
from app.api.schemas.device import (
    DevicePositionRequest,
    DevicePositionResponse,
    DeviceRegisterRequest,
    DeviceResponse,
)
from app.application.services.deactivate_device import (
    DeactivateDevice,
)
from app.application.services.record_device_position import (
    RecordDevicePosition,
)
from app.application.services.register_device import (
    RegisterDevice,
)
from app.infrastructure.repositories.postgresql_device_repository import (
    PostgreSQLDeviceRepository,
)
from app.infrastructure.repositories.postgresql_user_repository import (
    PostgreSQLUserRepository,
)


router = APIRouter(
    prefix="/devices",
    tags=["devices"],
)


def repositories():
    return (
        PostgreSQLUserRepository(),
        PostgreSQLDeviceRepository(),
    )


@router.put(
    "/current",
    response_model=DeviceResponse,
)
def register_current_device(
    request: DeviceRegisterRequest,
    identity: dict = Depends(get_current_identity),
):
    user_repository, device_repository = repositories()

    service = RegisterDevice(
        user_repository=user_repository,
        device_repository=device_repository,
    )

    return service.execute(
        firebase_uid=identity["uid"],
        installation_id=request.installation_id,
        platform=request.platform,
        fcm_token=request.fcm_token,
    )


@router.put(
    "/current/position",
    response_model=DevicePositionResponse,
)
def record_current_device_position(
    request: DevicePositionRequest,
    installation_id: UUID = Header(
        alias="X-Installation-ID",
    ),
    identity: dict = Depends(get_current_identity),
):
    user_repository, device_repository = repositories()

    service = RecordDevicePosition(
        user_repository=user_repository,
        device_repository=device_repository,
    )

    longitude, latitude = (
        request.position.coordinates
    )

    position = service.execute(
        firebase_uid=identity["uid"],
        installation_id=installation_id,
        longitude=longitude,
        latitude=latitude,
        accuracy_m=request.accuracy_m,
        heading_deg=request.heading_deg,
        measured_at=request.measured_at,
    )

    return {
        "position": {
            "type": "Point",
            "coordinates": [
                position.longitude,
                position.latitude,
            ],
        },
        "accuracy_m": position.accuracy_m,
        "heading_deg": position.heading_deg,
        "measured_at": position.measured_at,
        "received_at": position.received_at,
    }


@router.delete(
    "/current",
    status_code=status.HTTP_204_NO_CONTENT,
)
def deactivate_current_device(
    installation_id: UUID = Header(
        alias="X-Installation-ID",
    ),
    identity: dict = Depends(get_authenticated_identity),
):
    user_repository, device_repository = repositories()

    service = DeactivateDevice(
        user_repository=user_repository,
        device_repository=device_repository,
    )

    service.execute(
        firebase_uid=identity["uid"],
        installation_id=installation_id,
    )

    return Response(
        status_code=status.HTTP_204_NO_CONTENT,
    )
