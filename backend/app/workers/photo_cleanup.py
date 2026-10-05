"""Reconcile unused storage objects every five minutes; no mobile retry queue."""

import logging
import time

import psycopg

from app.application.services.clean_unused_photos import CleanUnusedPhotos
from app.dependencies.photo_storage import get_photo_storage
from app.domain.errors import PhotoStorageError
from app.infrastructure.repositories.postgresql_photo_repository import (
    PostgreSQLPhotoRepository,
)

logger = logging.getLogger(__name__)


def main():
    logging.basicConfig(level=logging.INFO)
    service = CleanUnusedPhotos(PostgreSQLPhotoRepository(), get_photo_storage())
    while True:
        try:
            deleted = service.execute()
            logger.info("Photo cleanup completed: %s unused objects deleted", deleted)
        except (psycopg.Error, PhotoStorageError):
            # Do not log SDK exception text: it may contain a signed URL.
            logger.warning("Photo cleanup dependency unavailable; retrying next scan")
        time.sleep(300)


if __name__ == "__main__":
    main()
