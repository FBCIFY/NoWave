from app.application.ports.user_repository import UserRepository
from app.domain.errors import (
    UserNotFoundError,
    UsernameAlreadyExistsError,
)
from app.domain.user import User


class UpdateUser:
    def __init__(self, user_repository: UserRepository):
        self.user_repository = user_repository

    def execute(
        self,
        firebase_uid: str,
        changes: dict,
    ) -> User:
        user = self.user_repository.get_by_firebase_uid(
            firebase_uid
        )

        if user is None:
            raise UserNotFoundError(
                "user profile not found"
            )

        if not changes:
            return user

        if "username" in changes:
            username = changes["username"].strip()

            existing_user = self.user_repository.get_by_username(
                username
            )

            if (
                existing_user is not None
                and existing_user.id != user.id
            ):
                raise UsernameAlreadyExistsError(
                    "username already exists"
                )

        user.update_profile(changes)

        return self.user_repository.update(
            user,
            fields=set(changes),
        )
