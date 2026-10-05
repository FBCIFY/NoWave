from fastapi.exceptions import RequestValidationError
from starlette.exceptions import HTTPException as StarletteHTTPException
from fastapi.responses import JSONResponse

from app.domain.errors import (
    BoatAlreadyExistsError,
    BoatNotFoundError,
    EmailNotVerifiedError,
    GpsPrecisionInsufficientError,
    InactiveUserError,
    InvalidObservedAtError,
    InvalidPhotoError,
    InvalidPositioningInputError,
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


REPORT_VALIDATION_CODES = {
    InvalidReportCategoryError: "invalid_report_category",
    InvalidReportDescriptionError: "invalid_report_description",
    InvalidReportPositionError: "invalid_report_position",
    InvalidObservedAtError: "invalid_observed_at",
}


def http_exception_handler(
    request,
    exc: StarletteHTTPException,
):
    error_codes = {
        "Authentication required": "authentication_required",
        "Invalid authentication token": "invalid_authentication_token",
    }

    if isinstance(exc.detail, str):
        message = exc.detail
        code = error_codes.get(
            exc.detail,
            f"http_{exc.status_code}",
        )
    else:
        message = "Request failed"
        code = f"http_{exc.status_code}"

    return JSONResponse(
        status_code=exc.status_code,
        content={
            "error": {
                "code": code,
                "message": message,
                "details": None,
            }
        },
    )


def report_not_found_handler(request, exc: ReportNotFoundError):
    return JSONResponse(
        status_code=404,
        content={
            "error": {
                "code": "report_not_found",
                "message": str(exc),
                "details": None,
            }
        },
    )


def report_validation_handler(request, exc):
    error_code = REPORT_VALIDATION_CODES[type(exc)]

    return JSONResponse(
        status_code=400,
        content={
            "error": {
                "code": error_code,
                "message": str(exc),
                "details": None,
            }
        },
    )


def report_client_id_conflict_handler(
    request,
    exc: ReportClientIdConflictError,
):
    return JSONResponse(
        status_code=409,
        content={
            "error": {
                "code": "report_client_id_conflict",
                "message": str(exc),
                "details": None,
            }
        },
    )


def inactive_user_handler(request, exc: InactiveUserError):
    return JSONResponse(
        status_code=403,
        content={
            "error": {
                "code": "user_inactive",
                "message": str(exc),
                "details": None,
            }
        },
    )


def email_not_verified_handler(request, exc: EmailNotVerifiedError):
    return JSONResponse(
        status_code=403,
        content={
            "error": {
                "code": "email_not_verified",
                "message": str(exc),
                "details": None,
            }
        },
    )


def user_already_exists_handler(request, exc: UserAlreadyExistsError):
    return JSONResponse(
        status_code=409,
        content={
            "error": {
                "code": "user_already_exists",
                "message": str(exc),
                "details": None,
            }
        },
    )


def username_already_exists_handler(request, exc: UsernameAlreadyExistsError):
    return JSONResponse(
        status_code=409,
        content={
            "error": {
                "code": "username_already_exists",
                "message": str(exc),
                "details": None,
            }
        },
    )


def user_not_found_handler(request, exc: UserNotFoundError):
    return JSONResponse(
        status_code=404,
        content={
            "error": {
                "code": "user_not_found",
                "message": str(exc),
                "details": None,
            }
        },
    )


def gps_precision_insufficient_handler(
    request,
    exc: GpsPrecisionInsufficientError,
):
    return JSONResponse(
        status_code=422,
        content={
            "error": {
                "code": "gps_precision_insufficient",
                "message": str(exc),
                "details": {
                    "accuracy_m": exc.accuracy_m,
                    "maximum_accuracy_m": 50,
                },
            }
        },
    )


def invalid_positioning_input_handler(
    request,
    exc: InvalidPositioningInputError,
):
    return JSONResponse(
        status_code=422,
        content={
            "error": {
                "code": "invalid_positioning_input",
                "message": str(exc),
                "details": None,
            }
        },
    )


def request_validation_error_handler(
    request,
    exc: RequestValidationError,
):
    details = [
        {
            "loc": list(error["loc"]),
            "msg": error["msg"],
            "type": error["type"],
        }
        for error in exc.errors()
    ]

    return JSONResponse(
        status_code=422,
        content={
            "error": {
                "code": "request_validation_error",
                "message": "Invalid request payload",
                "details": details,
            }
        },
    )


def boat_not_found_handler(request, exc: BoatNotFoundError):
    return JSONResponse(
        status_code=404,
        content={
            "error": {
                "code": "boat_not_found",
                "message": str(exc),
                "details": None,
            }
        },
    )


def boat_already_exists_handler(
    request,
    exc: BoatAlreadyExistsError,
):
    return JSONResponse(
        status_code=409,
        content={
            "error": {
                "code": "boat_already_exists",
                "message": str(exc),
                "details": None,
            }
        },
    )


def invalid_photo_handler(request, exc: InvalidPhotoError):
    return JSONResponse(
        status_code=422,
        content={
            "error": {
                "code": "invalid_photo",
                "message": str(exc),
                "details": None,
            }
        },
    )


def photo_upload_forbidden_handler(
    request,
    exc: PhotoUploadForbiddenError,
):
    return JSONResponse(
        status_code=403,
        content={
            "error": {
                "code": "photo_upload_forbidden",
                "message": str(exc),
                "details": None,
            }
        },
    )


def photo_already_uploaded_handler(
    request,
    exc: PhotoAlreadyUploadedError,
):
    return JSONResponse(
        status_code=409,
        content={
            "error": {
                "code": "photo_already_uploaded",
                "message": str(exc),
                "details": None,
            }
        },
    )


def photo_storage_error_handler(
    request,
    exc: PhotoStorageError,
):
    return JSONResponse(
        status_code=503,
        content={
            "error": {
                "code": "photo_storage_unavailable",
                "message": str(exc),
                "details": None,
            }
        },
    )


def dependency_unavailable_handler(request, exc):
    # Database and configuration exceptions can contain credentials or hostnames.
    return JSONResponse(
        status_code=503,
        content={
            "error": {
                "code": "dependency_unavailable",
                "message": "a required service is unavailable; please retry",
                "details": None,
            }
        },
    )
