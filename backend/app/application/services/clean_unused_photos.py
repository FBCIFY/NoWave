from datetime import UTC, datetime, timedelta
import logging
import re
from uuid import UUID

from app.application.ports.photo_repository import PhotoRepository
from app.application.ports.photo_storage import PhotoStoragePort
from app.domain.errors import PhotoStorageError

logger = logging.getLogger(__name__)
PHOTO_KEY = re.compile(r"reports/([0-9a-f-]{36})/[0-9a-f]{64}/[0-9a-f]{32}\.jpg")


class CleanUnusedPhotos:
    def __init__(
        self, photo_repository: PhotoRepository, photo_storage: PhotoStoragePort
    ):
        self.photo_repository = photo_repository
        self.photo_storage = photo_storage

    def execute(self, now: datetime | None = None) -> int:
        cutoff = (now or datetime.now(UTC)) - timedelta(hours=1)
        deleted = 0
        for stored in self.photo_storage.list_photos():
            match = PHOTO_KEY.fullmatch(stored.object_key)
            if match is None or stored.modified_at > cutoff:
                continue
            try:
                report_id = UUID(match[1])
            except ValueError:
                continue

            # Use the upload lock: a photo cannot be finalized while its object
            # is being deleted. Keep referenced photos, even if hidden or expired.
            with self.photo_repository.lock_for_upload(report_id) as session:
                if (
                    session.photo is not None
                    and session.photo.object_key == stored.object_key
                ):
                    continue
                try:
                    self.photo_storage.delete(stored.object_key)
                except PhotoStorageError:
                    logger.warning("Photo cleanup failed; the next scan will retry")
                else:
                    deleted += 1
        return deleted
