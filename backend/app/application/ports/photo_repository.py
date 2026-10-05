from abc import ABC, abstractmethod
from contextlib import AbstractContextManager
from dataclasses import dataclass
from uuid import UUID

from app.domain.report_photo import UploadStatus


@dataclass(frozen=True)
class PhotoUploadData:
    report_id: UUID
    author_id: UUID | None
    status: UploadStatus
    object_key: str | None
    size_bytes: int | None
    mime_type: str | None


class PhotoUploadSession(ABC):
    """One locked photo row. Changes commit when the session closes normally."""

    photo: PhotoUploadData | None

    @abstractmethod
    def mark_uploaded(self, object_key: str, size_bytes: int, mime_type: str) -> None:
        pass

    @abstractmethod
    def mark_failed(self) -> None:
        pass


class PhotoRepository(ABC):
    @abstractmethod
    def lock_for_upload(
        self, report_id: UUID
    ) -> AbstractContextManager[PhotoUploadSession]:
        """Serialize uploads and cleanup for this report until commit or rollback."""
        pass
