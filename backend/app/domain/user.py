from datetime import UTC, date, datetime
from enum import Enum
from uuid import UUID, uuid4

from app.domain.errors import (
    InvalidEmailError,
    InvalidFirebaseUidError,
    InvalidNationalityError,
    InvalidUsernameError,
)


class UserRole(str, Enum):
    USER = "user"
    ADMIN = "admin"


class UserStatus(str, Enum):
    ACTIVE = "active"
    SUSPENDED = "suspended"


def normalize_nationality(
    nationality: str,
) -> str:
    if not isinstance(nationality, str):
        raise InvalidNationalityError(
            "nationality must be a string"
        )

    nationality = nationality.strip()

    if (
        len(nationality) != 2
        or not nationality.isascii()
        or not nationality.isalpha()
    ):
        raise InvalidNationalityError(
            "nationality must use ISO alpha-2 format"
        )

    return nationality.upper()


class User:
    def __init__(
        self,
        firebase_uid: str,
        username: str,
        email: str,
        date_of_birth: date | None = None,
        nationality: str | None = None,
        role: UserRole = UserRole.USER,
        status: UserStatus = UserStatus.ACTIVE,
        show_user_name: bool = False,
        show_boat_info: bool = False,
        notifications_enabled: bool = False,
        id: UUID | None = None,
        created_at: datetime | None = None,
        updated_at: datetime | None = None,
    ):
        if not firebase_uid.strip():
            raise InvalidFirebaseUidError(
                "firebase_uid cannot be empty"
            )

        username = username.strip()

        if not username:
            raise InvalidUsernameError(
                "username cannot be empty"
            )

        if len(username) > 100:
            raise InvalidUsernameError(
                "username cannot exceed 100 characters"
            )

        if not email.strip():
            raise InvalidEmailError(
                "email cannot be empty"
            )

        if len(email.strip()) > 254:
            raise InvalidEmailError(
                "email cannot exceed 254 characters"
            )

        if nationality is not None:
            nationality = normalize_nationality(
                nationality
            )

        self.id = id if id is not None else uuid4()

        self.firebase_uid = firebase_uid.strip()
        self.username = username.strip()
        self.email = email.strip()

        self.date_of_birth = date_of_birth

        self.nationality = nationality

        self.role = role
        self.status = status

        self.show_user_name = show_user_name
        self.show_boat_info = show_boat_info
        self.notifications_enabled = notifications_enabled

        now = datetime.now(UTC)

        self.created_at = (
            created_at if created_at is not None else now
        )

        self.updated_at = (
            updated_at if updated_at is not None else now
        )

    def update_profile(self, changes: dict) -> None:
        if "username" in changes:
            username = changes["username"].strip()

            if not username:
                raise InvalidUsernameError(
                    "username cannot be empty"
                )

            if len(username) > 100:
                raise InvalidUsernameError(
                    "username cannot exceed 100 characters"
                )

            self.username = username

        if "date_of_birth" in changes:
            self.date_of_birth = changes["date_of_birth"]

        if "nationality" in changes:
            nationality = changes["nationality"]

            if nationality is None:
                self.nationality = None
            else:
                self.nationality = normalize_nationality(
                    nationality
                )

        if "show_user_name" in changes:
            self.show_user_name = changes["show_user_name"]

        if "show_boat_info" in changes:
            self.show_boat_info = changes["show_boat_info"]

        if "notifications_enabled" in changes:
            self.notifications_enabled = changes[
                "notifications_enabled"
            ]

        self.updated_at = datetime.now(UTC)
