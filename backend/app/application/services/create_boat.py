from app.application.ports.boat_repository import BoatRepository
from app.application.ports.user_repository import UserRepository
from app.domain.boat import Boat, BoatType
from app.domain.errors import (
    BoatAlreadyExistsError,
    UserNotFoundError,
)


class CreateBoat:
    def __init__(
        self,
        user_repository: UserRepository,
        boat_repository: BoatRepository,
    ):
        self.user_repository = user_repository
        self.boat_repository = boat_repository

    def execute(
        self,
        firebase_uid: str,
        boat_type: BoatType,
        name: str | None = None,
        flag_country: str | None = None,
    ) -> Boat:
        user = self.user_repository.get_by_firebase_uid(
            firebase_uid
        )

        if user is None:
            raise UserNotFoundError(
                "user profile not found"
            )

        existing_boat = self.boat_repository.get_by_user_id(
            user.id
        )

        if existing_boat is not None:
            raise BoatAlreadyExistsError(
                "boat already exists"
            )

        boat = Boat(
            user_id=user.id,
            boat_type=boat_type,
            name=name,
            flag_country=flag_country,
        )

        return self.boat_repository.save(boat)
