from contextlib import contextmanager
from uuid import UUID

from app.application.ports.photo_repository import (
    PhotoRepository,
    PhotoUploadData,
    PhotoUploadSession,
)
from app.domain.report_photo import UploadStatus
from app.infrastructure.database.connection import database_connection


class PostgreSQLPhotoRepository(PhotoRepository):
    @contextmanager
    def lock_for_upload(self, report_id: UUID):
        with database_connection() as connection:
            # Bound waits and release the lock if a worker disappears during storage I/O.
            connection.execute("SET LOCAL lock_timeout = '3s'")
            connection.execute("SET LOCAL idle_in_transaction_session_timeout = '15s'")
            row = connection.execute(
                """
                SELECT rp.report_id, r.author_id, rp.upload_status,
                       rp.object_key, rp.size_bytes, rp.mime_type
                FROM nowave.report_photos AS rp
                JOIN nowave.reports AS r ON r.id = rp.report_id
                WHERE rp.report_id = %s
                FOR UPDATE OF rp
                """,
                (report_id,),
            ).fetchone()
            photo = None
            if row is not None:
                photo = PhotoUploadData(
                    report_id=row[0],
                    author_id=row[1],
                    status=UploadStatus(row[2]),
                    object_key=row[3],
                    size_bytes=row[4],
                    mime_type=row[5],
                )
            yield PostgreSQLPhotoUploadSession(connection, photo)


class PostgreSQLPhotoUploadSession(PhotoUploadSession):
    def __init__(self, connection, photo: PhotoUploadData | None):
        self.connection = connection
        self.photo = photo

    def mark_uploaded(self, object_key: str, size_bytes: int, mime_type: str) -> None:
        self.connection.execute(
            """
            UPDATE nowave.report_photos
            SET upload_status = 'uploaded', object_key = %s,
                size_bytes = %s, mime_type = %s,
                uploaded_at = now(), updated_at = now()
            WHERE report_id = %s
            """,
            (object_key, size_bytes, mime_type, self.photo.report_id),
        )

    def mark_failed(self) -> None:
        self.connection.execute(
            """
            UPDATE nowave.report_photos
            SET upload_status = 'failed', updated_at = now()
            WHERE report_id = %s AND upload_status <> 'uploaded'
            """,
            (self.photo.report_id,),
        )
