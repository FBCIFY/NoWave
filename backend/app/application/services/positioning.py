from app.application.ports.user_repository import (
    UserRepository,
)
from app.domain.errors import (
    InactiveUserError,
    UserNotFoundError,
)
from app.domain.positioning import (
    PositionEstimateResult,
    PositioningMeasurements,
    estimate_position,
)
from app.domain.user import UserStatus


class PositioningService:
    def __init__(
        self,
        user_repository: UserRepository,
    ):
        self.user_repository = user_repository

    def estimate(
        self,
        firebase_uid: str,
        measurements: PositioningMeasurements,
    ) -> PositionEstimateResult:
        user = self.user_repository.get_by_firebase_uid(
            firebase_uid
        )

        if user is None:
            raise UserNotFoundError(
                "NoWave user not found"
            )

        if user.status != UserStatus.ACTIVE:
            raise InactiveUserError(
                "user is not active"
            )

        return estimate_position(
            measurements
        )
