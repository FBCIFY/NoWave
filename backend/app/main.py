from fastapi import FastAPI
from app.config.production import configure_production, is_production

from app.api.errors.handlers import (
    boat_already_exists_handler,
    boat_not_found_handler,
    email_not_verified_handler,
    gps_precision_insufficient_handler,
    inactive_user_handler,
    invalid_positioning_input_handler,
    report_client_id_conflict_handler,
    report_not_found_handler,
    report_validation_handler,
    user_already_exists_handler,
    user_not_found_handler,
    username_already_exists_handler,
)
from app.api.router import router as api_router
from app.api.routes.health import router as health_router
from app.domain.errors import (
    BoatAlreadyExistsError,
    BoatNotFoundError,
    EmailNotVerifiedError,
    GpsPrecisionInsufficientError,
    InactiveUserError,
    InvalidObservedAtError,
    InvalidPositioningInputError,
    InvalidReportCategoryError,
    InvalidReportDescriptionError,
    InvalidReportPositionError,
    ReportClientIdConflictError,
    ReportNotFoundError,
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

app.include_router(health_router)
app.include_router(api_router)

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
