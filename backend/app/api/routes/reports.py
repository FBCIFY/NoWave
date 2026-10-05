from uuid import UUID

from fastapi import (
    APIRouter,
    Depends,
    File,
    UploadFile,
    Response,
    status,
)

from app.api.dependencies.auth import get_current_identity
from app.api.schemas.position_estimate import (
    PositionEstimateRequest,
)
from app.api.schemas.report import (
    GeoJSONPoint,
    ReportCreateRequest,
    ReportPhotoResponse,
    PhotoMetadataResponse,
    ReportResponse,
)
from app.application.services.create_report import CreateReport
from app.application.services.upload_report_photo import (
    UploadReportPhoto,
)
from app.dependencies.photo_storage import get_photo_storage
from app.domain.errors import InvalidPhotoError
from app.domain.positioning import PositioningMeasurements
from app.infrastructure.adapters.jpeg_validator import JpegValidator, MAX_PHOTO_BYTES
from app.infrastructure.repositories.postgresql_photo_repository import (
    PostgreSQLPhotoRepository,
)
from app.infrastructure.repositories.postgresql_report_repository import (
    PostgreSQLReportRepository,
)
from app.infrastructure.repositories.postgresql_user_repository import (
    PostgreSQLUserRepository,
)


router = APIRouter(
    prefix="/reports",
    tags=["reports"],
)


def build_positioning(
    positioning: PositionEstimateRequest | None,
) -> PositioningMeasurements | None:
    if positioning is None:
        return None

    longitude = positioning.observer_position.coordinates[0]

    latitude = positioning.observer_position.coordinates[1]

    return PositioningMeasurements(
        observer_longitude=longitude,
        observer_latitude=latitude,
        gps_accuracy_m=positioning.gps_accuracy_m,
        azimuth_deg=positioning.azimuth_deg,
        inclination_deg=positioning.inclination_deg,
        camera_height_m=positioning.camera_height_m,
        camera_height_source=(positioning.camera_height_source),
        camera_height_uncertainty_m=(positioning.camera_height_uncertainty_m),
        focal_length_mm=positioning.focal_length_mm,
        zoom_ratio=positioning.zoom_ratio,
        captured_at=positioning.captured_at,
    )


@router.post(
    "",
    response_model=ReportResponse,
    status_code=status.HTTP_201_CREATED,
)
def create_report(
    request: ReportCreateRequest,
    response: Response,
    identity: dict = Depends(get_current_identity),
):
    user_repository = PostgreSQLUserRepository()
    report_repository = PostgreSQLReportRepository()

    service = CreateReport(
        user_repository=user_repository,
        report_repository=report_repository,
    )

    longitude = request.final_position.coordinates[0]

    latitude = request.final_position.coordinates[1]

    positioning = build_positioning(request.positioning)

    result = service.execute(
        firebase_uid=identity["uid"],
        client_report_id=request.client_report_id,
        category=request.category,
        longitude=longitude,
        latitude=latitude,
        observed_at=request.observed_at,
        description=request.description,
        positioning_mode=request.positioning_mode,
        positioning=positioning,
    )

    if not result.created:
        response.status_code = status.HTTP_200_OK

    report = result.report

    photo = None

    if report.positioning_mode.value == "photo":
        photo_status = report_repository.get_photo_status(report.id)

        if photo_status is not None:
            photo = ReportPhotoResponse(
                status=photo_status.value,
                url=None,
            )

    return ReportResponse(
        id=report.id,
        author_id=report.author_id,
        client_report_id=report.client_report_id,
        category=report.category,
        positioning_mode=report.positioning_mode,
        description=report.description,
        final_position=GeoJSONPoint(
            type="Point",
            coordinates=[
                report.longitude,
                report.latitude,
            ],
        ),
        observed_at=report.observed_at,
        expires_at=report.expires_at,
        status=report.status,
        version=report.version,
        created_at=report.created_at,
        updated_at=report.updated_at,
        photo=photo,
    )


@router.post(
    "/{report_id}/photo",
    response_model=PhotoMetadataResponse,
    status_code=status.HTTP_201_CREATED,
    responses={200: {"model": PhotoMetadataResponse, "description": "Identical retry"}},
)
def upload_report_photo(
    report_id: UUID,
    response: Response,
    file: UploadFile = File(...),
    identity: dict = Depends(get_current_identity),
):
    # A sync route runs decoding, PostgreSQL and S3 in FastAPI's thread pool.
    content = file.file.read(MAX_PHOTO_BYTES + 1)
    if len(content) > MAX_PHOTO_BYTES:
        raise InvalidPhotoError("photo size must be between 1 and 500000 bytes")

    service = UploadReportPhoto(
        user_repository=PostgreSQLUserRepository(),
        photo_repository=PostgreSQLPhotoRepository(),
        image_validator=JpegValidator(),
        photo_storage=get_photo_storage(),
    )
    result = service.execute(
        firebase_uid=identity["uid"],
        report_id=report_id,
        content=content,
        declared_mime_type=file.content_type,
    )
    if not result.created:
        response.status_code = status.HTTP_200_OK
    return PhotoMetadataResponse(
        report_id=result.report_id,
        upload_status=result.upload_status,
        size_bytes=result.size_bytes,
        mime_type=result.mime_type,
    )
