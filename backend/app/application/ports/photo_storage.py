from abc import ABC, abstractmethod
from collections.abc import Iterator
from dataclasses import dataclass
from datetime import datetime, timedelta


@dataclass(frozen=True)
class StoredPhoto:
    object_key: str
    modified_at: datetime


class PhotoStoragePort(ABC):
    """Object-storage boundary used by photo application services."""

    @abstractmethod
    def store(
        self,
        object_key: str,
        content: bytes,
        mime_type: str,
    ) -> None:
        """Store content at this attempt's unique key, idempotently."""

        pass

    @abstractmethod
    def delete(self, object_key: str) -> None:
        """Delete an object; missing objects must be treated as success."""

        pass

    @abstractmethod
    def create_read_url(
        self,
        object_key: str,
        expires_in: timedelta,
    ) -> str:
        """Return an authorized, temporary read URL."""

        pass

    @abstractmethod
    def list_photos(self) -> Iterator[StoredPhoto]:
        """List objects in the reports/ prefix, following storage pagination."""
        pass
