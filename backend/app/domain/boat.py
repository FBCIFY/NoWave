from datetime import UTC, datetime
from enum import Enum
from uuid import UUID, uuid4


class BoatType(str, Enum):
    SAILBOAT = "voilier"
    MOTORBOAT = "bateau_moteur"
    CATAMARAN = "catamaran"
    RIB = "semi_rigide"
    JET_SKI = "jet_ski"
    OTHER = "autre"


def _normalize_flag_country(
    flag_country: str,
) -> str:
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


class Boat:
    def __init__(
        self,
        user_id: UUID,
        boat_type: BoatType,
        name: str | None = None,
        flag_country: str | None = None,
        id: UUID | None = None,
        created_at: datetime | None = None,
        updated_at: datetime | None = None,
    ):
        if user_id is None:
            raise ValueError("user_id is required")

        try:
            boat_type = BoatType(boat_type)
        except ValueError as error:
            raise ValueError("invalid boat type") from error

        if name is not None:
            name = name.strip()

            if len(name) > 100:
                raise ValueError(
                    "boat name cannot exceed 100 characters"
                )

            if not name:
                name = None

        if flag_country is not None:
            flag_country = _normalize_flag_country(
                flag_country
            )

        self.id = id if id is not None else uuid4()
        self.user_id = user_id
        self.name = name
        self.boat_type = boat_type
        self.flag_country = flag_country

        now = datetime.now(UTC)

        self.created_at = (
            created_at if created_at is not None else now
        )

        self.updated_at = (
            updated_at if updated_at is not None else now
        )

    def update(self, changes: dict) -> None:
        if "name" in changes:
            name = changes["name"]

            if name is None:
                self.name = None
            else:
                name = name.strip()

                if len(name) > 100:
                    raise ValueError(
                        "boat name cannot exceed 100 characters"
                    )

                self.name = name if name else None

        if "boat_type" in changes:
            try:
                self.boat_type = BoatType(
                    changes["boat_type"]
                )
            except ValueError as error:
                raise ValueError(
                    "invalid boat type"
                ) from error

        if "flag_country" in changes:
            flag_country = changes["flag_country"]

            if flag_country is None:
                self.flag_country = None
            else:
                self.flag_country = (
                    _normalize_flag_country(
                        flag_country
                    )
                )

        self.updated_at = datetime.now(UTC)
