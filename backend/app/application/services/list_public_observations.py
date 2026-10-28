import base64
import binascii
from dataclasses import dataclass
from datetime import UTC, datetime
from uuid import UUID

from app.application.ports.public_observation_reader import (
    ObservationQuery,
    PublicObservation,
    PublicObservationReader,
)


def decode_observation_cursor(value: str | None) -> tuple[datetime, UUID] | None:
    if value is None:
        return None
    try:
        decoded = base64.b64decode(value + "=" * (-len(value) % 4), altchars=b"-_", validate=True)
        timestamp, identifier = decoded.decode("ascii").split("|", 1)
        observed_at = datetime.fromisoformat(timestamp)
        if observed_at.tzinfo is None or observed_at.utcoffset() is None:
            raise ValueError("cursor timestamp must include a timezone")
        return observed_at.astimezone(UTC), UUID(identifier)
    except (ValueError, UnicodeError, binascii.Error, OverflowError) as error:
        raise ValueError("Invalid observation cursor") from error


def encode_observation_cursor(observation: PublicObservation) -> str:
    value = f"{observation.observed_at.isoformat()}|{observation.id}".encode("ascii")
    return base64.urlsafe_b64encode(value).decode("ascii").rstrip("=")


@dataclass(frozen=True)
class PublicObservationPage:
    items: list[PublicObservation]
    has_more: bool
    next_cursor: str | None


class ListPublicObservations:
    def __init__(self, reader: PublicObservationReader):
        self.reader = reader

    def execute(self, query: ObservationQuery) -> PublicObservationPage:
        rows = self.reader.list_active(query)
        items = rows[:query.limit]
        has_more = len(rows) > query.limit
        return PublicObservationPage(
            items=items,
            has_more=has_more,
            next_cursor=encode_observation_cursor(items[-1]) if has_more else None,
        )
