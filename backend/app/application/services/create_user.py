from app.application.ports.user_repository import UserRepository
from app.domain.errors import (
    EmailNotVerifiedError,
    UserAlreadyExistsError,
    UsernameAlreadyExistsError,
)
from app.domain.user import User


class CreateUser:
    def __init__(self, user_repository: UserRepository):
        self.user_repository = user_repository

    def execute(
        self,
        firebase_uid: str,
        username: str,
        email: str,
        email_verified: bool,
    ) -> User:
        if not email_verified:
            raise EmailNotVerifiedError(
                "email must be verified"
            )

        user = User(
            firebase_uid=firebase_uid,
            username=username,
            email=email,
        )

        existing_user = self.user_repository.get_by_firebase_uid(
            user.firebase_uid
        )

        if existing_user is not None:
            raise UserAlreadyExistsError(
                "user profile already exists"
            )

        existing_username = self.user_repository.get_by_username(
            user.username
        )

        if existing_username is not None:
            raise UsernameAlreadyExistsError(
                "username already exists"
            )

        return self.user_repository.save(user)
