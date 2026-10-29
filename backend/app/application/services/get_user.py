from app.application.ports.user_repository import UserRepository
from app.domain.errors import UserNotFoundError
from app.domain.user import User


class GetUser:
    def __init__(self, user_repository: UserRepository):
        self.user_repository = user_repository

    def execute(self, firebase_uid: str) -> User:
        user = self.user_repository.get_by_firebase_uid(firebase_uid)

        if user is None:
            raise UserNotFoundError(
                "user profile not found"
            )

        return user
