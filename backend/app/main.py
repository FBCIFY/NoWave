import psycopg
from fastapi import FastAPI
from fastapi.exceptions import RequestValidationError
from starlette.exceptions import HTTPException as StarletteHTTPException
from app.config.production import configure_production, is_production
from app.config.settings import ConfigurationError
from app.api.photo_upload_limit import PhotoUploadLimitMiddleware

from app.api.errors.handlers import (
    dependency_unavailable_handler,
    device_conflict_handler,
    device_not_found_handler,
    device_position_future_handler,
    device_position_stale_handler,
    http_exception_handler,
    boat_already_exists_handler,
    boat_not_found_handler,
    email_not_verified_handler,
    gps_precision_insufficient_handler,
    inactive_user_handler,
    invalid_nationality_handler,
    invalid_positioning_input_handler,
    invalid_photo_handler,
    photo_already_uploaded_handler,
    photo_storage_error_handler,
    photo_upload_forbidden_handler,
    report_client_id_conflict_handler,
    report_not_found_handler,
    request_validation_error_handler,
    report_validation_handler,
    user_already_exists_handler,
    user_not_found_handler,
    username_already_exists_handler,
)
from app.api.router import router as api_router
from app.api.routes.health import router as health_router
from app.domain.errors import (
    DeviceConflictError,
    DeviceNotFoundError,
    DevicePositionFutureError,
    DevicePositionStaleError,
    BoatAlreadyExistsError,
    BoatNotFoundError,
    EmailNotVerifiedError,
    GpsPrecisionInsufficientError,
    InactiveUserError,
    InvalidNationalityError,
    InvalidObservedAtError,
    InvalidPositioningInputError,
    InvalidPhotoError,
    InvalidReportCategoryError,
    InvalidReportDescriptionError,
    InvalidReportPositionError,
    ReportClientIdConflictError,
    ReportNotFoundError,
    PhotoAlreadyUploadedError,
    PhotoStorageError,
    PhotoUploadForbiddenError,
    UserAlreadyExistsError,
    UserNotFoundError,
    UsernameAlreadyExistsError,
)


app = FastAPI(
    docs_url=None if is_production() else "/docs",
    redoc_url=None if is_production() else "/redoc",
    openapi_url=None if is_production() else "/openapi.json",
)
configure_production(app)
app.add_middleware(PhotoUploadLimitMiddleware)
for error_type in (
    psycopg.OperationalError,
    psycopg.InterfaceError,
    ConfigurationError,
):
    app.add_exception_handler(error_type, dependency_unavailable_handler)

app.include_router(health_router)
app.include_router(api_router)

app.add_exception_handler(
    StarletteHTTPException,
    http_exception_handler,
)

app.add_exception_handler(
    RequestValidationError,
    request_validation_error_handler,
)

app.add_exception_handler(
    ReportNotFoundError,
    report_not_found_handler,
)

app.add_exception_handler(
    InvalidReportCategoryError,
    report_validation_handler,
)

app.add_exception_handler(
    InvalidReportDescriptionError,
    report_validation_handler,
)

app.add_exception_handler(
    InvalidReportPositionError,
    report_validation_handler,
)

app.add_exception_handler(
    InvalidObservedAtError,
    report_validation_handler,
)

app.add_exception_handler(
    ReportClientIdConflictError,
    report_client_id_conflict_handler,
)

app.add_exception_handler(
    InactiveUserError,
    inactive_user_handler,
)

app.add_exception_handler(
    EmailNotVerifiedError,
    email_not_verified_handler,
)

app.add_exception_handler(
    UserAlreadyExistsError,
    user_already_exists_handler,
)

app.add_exception_handler(
    UsernameAlreadyExistsError,
    username_already_exists_handler,
)

app.add_exception_handler(
    UserNotFoundError,
    user_not_found_handler,
)


app.add_exception_handler(
    InvalidNationalityError,
    invalid_nationality_handler,
)

app.add_exception_handler(
    GpsPrecisionInsufficientError,
    gps_precision_insufficient_handler,
)


app.add_exception_handler(
    InvalidPositioningInputError,
    invalid_positioning_input_handler,
)


app.add_exception_handler(
    BoatNotFoundError,
    boat_not_found_handler,
)

app.add_exception_handler(
    BoatAlreadyExistsError,
    boat_already_exists_handler,
)

app.add_exception_handler(
    InvalidPhotoError,
    invalid_photo_handler,
)

app.add_exception_handler(
    PhotoUploadForbiddenError,
    photo_upload_forbidden_handler,
)

app.add_exception_handler(
    PhotoAlreadyUploadedError,
    photo_already_uploaded_handler,
)

app.add_exception_handler(
    PhotoStorageError,
    photo_storage_error_handler,
)

app.add_exception_handler(
    DeviceConflictError,
    device_conflict_handler,
)

app.add_exception_handler(
    DeviceNotFoundError,
    device_not_found_handler,
)

app.add_exception_handler(
    DevicePositionFutureError,
    device_position_future_handler,
)

app.add_exception_handler(
    DevicePositionStaleError,
    device_position_stale_handler,
)
