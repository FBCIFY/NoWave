from datetime import date, datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.domain.errors import InvalidNationalityError
from app.domain.user import (
    UserRole,
    UserStatus,
    normalize_nationality,
)


class UserCreateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    username: str = Field(min_length=1, max_length=100)

    @field_validator("username")
    @classmethod
    def clean_username(cls, username: str) -> str:
        username = username.strip()

        if not username:
            raise ValueError("username cannot be empty")

        return username


class UserUpdateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    username: str | None = Field(
        default=None,
        min_length=1,
        max_length=100,
    )
    date_of_birth: date | None = None
    nationality: str | None = Field(
        default=None,
        min_length=2,
        max_length=2,
    )
    show_user_name: bool | None = None
    show_boat_info: bool | None = None
    notifications_enabled: bool | None = None

    @field_validator(
        "username",
        "show_user_name",
        "show_boat_info",
        "notifications_enabled",
    )
    @classmethod
    def required_fields_cannot_be_null(cls, value):
        if value is None:
            raise ValueError("field cannot be null")

        return value

    @field_validator("username")
    @classmethod
    def clean_username(cls, username: str) -> str:
        username = username.strip()

        if not username:
            raise ValueError("username cannot be empty")

        return username

    @field_validator(
        "nationality",
        mode="before",
    )
    @classmethod
    def clean_nationality(
        cls,
        nationality,
    ) -> str | None:
        if nationality is None:
            return None

        if not isinstance(nationality, str):
            raise ValueError(
                "nationality must be a string"
            )

        try:
            return normalize_nationality(
                nationality
            )
        except InvalidNationalityError as exc:
            raise ValueError(str(exc)) from exc


class UserProfileResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    username: str
    date_of_birth: date | None
    nationality: str | None
    role: UserRole
    status: UserStatus
    show_user_name: bool
    show_boat_info: bool
    notifications_enabled: bool
    created_at: datetime
    updated_at: datetime
