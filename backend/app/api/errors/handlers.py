from fastapi.responses import JSONResponse

from app.domain.errors import (
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


REPORT_VALIDATION_CODES = {
    InvalidReportCategoryError: "INVALID_REPORT_CATEGORY",
    InvalidReportDescriptionError: "INVALID_REPORT_DESCRIPTION",
    InvalidReportPositionError: "INVALID_REPORT_POSITION",
    InvalidObservedAtError: "INVALID_OBSERVED_AT",
}


def report_not_found_handler(request, exc: ReportNotFoundError):
    return JSONResponse(
        status_code=404,
        content={
            "error": {
                "code": "REPORT_NOT_FOUND",
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
                "code": "REPORT_CLIENT_ID_CONFLICT",
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
                "code": "USER_INACTIVE",
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
                "code": "EMAIL_NOT_VERIFIED",
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
                "code": "USER_ALREADY_EXISTS",
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
                "code": "USERNAME_ALREADY_EXISTS",
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
                "code": "USER_NOT_FOUND",
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
                "code": "INVALID_POSITIONING_INPUT",
                "message": str(exc),
                "details": None,
            }
        },
    )
