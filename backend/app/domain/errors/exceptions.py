class DomainError(Exception):
    pass


class ReportNotFoundError(DomainError):
    pass


class InvalidFirebaseUidError(DomainError):
    pass


class InvalidUsernameError(DomainError):
    pass


class InvalidEmailError(DomainError):
    pass


class InvalidNationalityError(DomainError):
    pass


class UserAlreadyExistsError(DomainError):
    pass


class UsernameAlreadyExistsError(DomainError):
    pass


class UserNotFoundError(DomainError):
    pass


class EmailNotVerifiedError(DomainError):
    pass


class InvalidReportCategoryError(DomainError):
    pass


class InvalidReportDescriptionError(DomainError):
    pass


class InvalidReportPositionError(DomainError):
    pass


class InvalidObservedAtError(DomainError):
    pass


class InactiveUserError(DomainError):
    pass


class ReportClientIdConflictError(DomainError):
    pass


class GpsPrecisionInsufficientError(DomainError):
    def __init__(
        self,
        accuracy_m: float,
    ):
        self.accuracy_m = accuracy_m

        super().__init__("La précision GPS doit être de 50 mètres ou meilleure.")


class InvalidPositioningInputError(DomainError):
    pass


class BoatAlreadyExistsError(DomainError):
    pass


class BoatNotFoundError(DomainError):
    pass


class InvalidPhotoError(DomainError):
    pass


class PhotoUploadForbiddenError(DomainError):
    pass


class PhotoAlreadyUploadedError(DomainError):
    pass


class PhotoStorageError(DomainError):
    pass


class DeviceConflictError(DomainError):
    pass


class DeviceNotFoundError(DomainError):
    pass


class DevicePositionStaleError(DomainError):
    pass


class DevicePositionFutureError(DomainError):
    def __init__(
        self,
        maximum_future_seconds: int,
    ):
        self.maximum_future_seconds = maximum_future_seconds

        super().__init__(
            "position measurement is too far in the future"
        )
