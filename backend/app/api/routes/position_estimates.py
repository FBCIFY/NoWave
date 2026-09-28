from fastapi import (
    APIRouter,
    Depends,
)

from app.api.dependencies.auth import (
    get_current_identity,
)
from app.api.schemas.position_estimate import (
    PositionEstimatePoint,
    PositionEstimateRequest,
    PositionEstimateResponse,
)
from app.application.services.positioning import (
    PositioningService,
)
from app.domain.positioning import (
    PositioningMeasurements,
)
from app.infrastructure.repositories.postgresql_user_repository import (
    PostgreSQLUserRepository,
)


router = APIRouter(
    prefix="/position-estimates",
    tags=["position-estimates"],
)


@router.post(
    "",
    response_model=PositionEstimateResponse,
)
def create_position_estimate(
    request: PositionEstimateRequest,
    identity: dict = Depends(
        get_current_identity
    ),
):
    longitude = (
        request.observer_position.coordinates[0]
    )

    latitude = (
        request.observer_position.coordinates[1]
    )

    measurements = PositioningMeasurements(
        observer_longitude=longitude,
        observer_latitude=latitude,
        gps_accuracy_m=request.gps_accuracy_m,
        azimuth_deg=request.azimuth_deg,
        inclination_deg=request.inclination_deg,
        camera_height_m=request.camera_height_m,
        camera_height_source=(
            request.camera_height_source
        ),
        camera_height_uncertainty_m=(
            request.camera_height_uncertainty_m
        ),
        focal_length_mm=request.focal_length_mm,
        zoom_ratio=request.zoom_ratio,
        captured_at=request.captured_at,
    )

    service = PositioningService(
        user_repository=(
            PostgreSQLUserRepository()
        ),
    )

    result = service.estimate(
        firebase_uid=identity["uid"],
        measurements=measurements,
    )

    if not result.available:
        return PositionEstimateResponse(
            estimated_position=None,
            estimated_distance_m=None,
        )

    return PositionEstimateResponse(
        estimated_position=(
            PositionEstimatePoint(
                type="Point",
                coordinates=[
                    result.longitude,
                    result.latitude,
                ],
            )
        ),
        estimated_distance_m=(
            result.distance_m
        ),
    )
