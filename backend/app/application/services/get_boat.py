from app.application.ports.boat_repository import BoatRepository
from app.application.ports.user_repository import UserRepository
from app.domain.boat import Boat
from app.domain.errors import (
    BoatNotFoundError,
    UserNotFoundError,
)


class GetBoat:
    def __init__(
        self,
        user_repository: UserRepository,
        boat_repository: BoatRepository,
    ):
        self.user_repository = user_repository
        self.boat_repository = boat_repository

    def execute(self, firebase_uid: str) -> Boat:
        user = self.user_repository.get_by_firebase_uid(
            firebase_uid
        )

        if user is None:
            raise UserNotFoundError(
                "user profile not found"
            )

        boat = self.boat_repository.get_by_user_id(
            user.id
        )

        if boat is None:
            raise BoatNotFoundError(
                "boat not found"
            )

        return boat
