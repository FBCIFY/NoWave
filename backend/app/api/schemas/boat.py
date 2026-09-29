from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.domain.boat import BoatType


class BoatCreateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    boat_type: BoatType
    name: str | None = Field(
        default=None,
        max_length=100,
    )
    flag_country: str | None = Field(
        default=None,
        min_length=2,
        max_length=2,
    )

    @field_validator("flag_country")
    @classmethod
    def normalize_flag_country(
        cls,
        flag_country: str | None,
    ) -> str | None:
        if flag_country is None:
            return None

        return flag_country.upper()


class BoatUpdateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    boat_type: BoatType | None = None
    name: str | None = Field(
        default=None,
        max_length=100,
    )
    flag_country: str | None = Field(
        default=None,
        min_length=2,
        max_length=2,
    )

    @field_validator("boat_type")
    @classmethod
    def boat_type_cannot_be_null(
        cls,
        boat_type: BoatType | None,
    ) -> BoatType:
        if boat_type is None:
            raise ValueError("boat_type cannot be null")

        return boat_type

    @field_validator("flag_country")
    @classmethod
    def normalize_flag_country(
        cls,
        flag_country: str | None,
    ) -> str | None:
        if flag_country is None:
            return None

        return flag_country.upper()


class BoatResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    name: str | None
    boat_type: BoatType
    flag_country: str | None
    created_at: datetime
    updated_at: datetime
