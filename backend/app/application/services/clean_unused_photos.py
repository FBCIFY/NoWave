from datetime import UTC, datetime, timedelta
from itertools import islice
import logging
import re
from uuid import UUID

from app.application.ports.photo_repository import PhotoRepository
from app.application.ports.photo_storage import PhotoStoragePort
from app.domain.errors import PhotoStorageError

logger = logging.getLogger(__name__)
PHOTO_KEY = re.compile(r"reports/([0-9a-f-]{36})/[0-9a-f]{64}/[0-9a-f]{32}\.jpg")


class CleanUnusedPhotos:
    batch_size = 250

    def __init__(
        self, photo_repository: PhotoRepository, photo_storage: PhotoStoragePort
    ):
        self.photo_repository = photo_repository
        self.photo_storage = photo_storage

    def execute(self, now: datetime | None = None) -> int:
        cutoff = (now or datetime.now(UTC)) - timedelta(hours=1)
        deleted = 0
        candidates = self._candidates(cutoff)
        while batch := list(islice(candidates, self.batch_size)):
            referenced = self.photo_repository.referenced_keys(
                list({report_id for report_id, _ in batch})
            )
            for report_id, stored in batch:
                if stored.object_key in referenced:
                    continue
                # References may change after the batch read. Upload and deletion
                # still serialize on the same row, and we recheck after waiting.
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

    def _candidates(self, cutoff):
        for stored in self.photo_storage.list_photos():
            match = PHOTO_KEY.fullmatch(stored.object_key)
            if match is None or stored.modified_at > cutoff:
                continue
            try:
                report_id = UUID(match[1])
            except ValueError:
                continue

            yield report_id, stored
