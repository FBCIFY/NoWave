from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.domain.boat import BoatType


def normalize_flag_country(
    flag_country: str | None,
) -> str | None:
    if flag_country is None:
        return None

    flag_country = flag_country.strip()

    if (
        len(flag_country) != 2
        or not flag_country.isascii()
        or not flag_country.isalpha()
    ):
        raise ValueError(
            "flag_country must contain exactly 2 letters"
        )

    return flag_country.upper()


class BoatCreateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    boat_type: BoatType
    name: str | None = Field(
        default=None,
        max_length=100,
    )
    flag_country: str | None = None

    @field_validator(
        "flag_country",
        mode="before",
    )
    @classmethod
    def validate_flag_country(
        cls,
        flag_country: str | None,
    ) -> str | None:
        return normalize_flag_country(
            flag_country
        )


class BoatUpdateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    boat_type: BoatType | None = None
    name: str | None = Field(
        default=None,
        max_length=100,
    )
    flag_country: str | None = None

    @field_validator("boat_type")
    @classmethod
    def boat_type_cannot_be_null(
        cls,
        boat_type: BoatType | None,
    ) -> BoatType:
        if boat_type is None:
            raise ValueError(
                "boat_type cannot be null"
            )

        return boat_type

    @field_validator(
        "flag_country",
        mode="before",
    )
    @classmethod
    def validate_flag_country(
        cls,
        flag_country: str | None,
    ) -> str | None:
        return normalize_flag_country(
            flag_country
        )


class BoatResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    name: str | None
    boat_type: BoatType
    flag_country: str | None
    created_at: datetime
    updated_at: datetime
