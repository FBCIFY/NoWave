from collections.abc import Iterator
from datetime import timedelta

import boto3
from botocore.config import Config
from botocore.exceptions import BotoCoreError, ClientError

from app.application.ports.photo_storage import PhotoStoragePort, StoredPhoto
from app.config.settings import PhotoStorageSettings
from app.domain.errors import PhotoStorageError


class ScalewayPhotoStorageAdapter(PhotoStoragePort):
    def __init__(self, settings: PhotoStorageSettings):
        self.bucket = settings.bucket
        self.client = boto3.client(
            "s3",
            endpoint_url=settings.endpoint_url,
            region_name=settings.region,
            aws_access_key_id=settings.access_key,
            aws_secret_access_key=settings.secret_key,
            config=Config(
                signature_version="s3v4",
                connect_timeout=2,
                read_timeout=5,
                retries={"total_max_attempts": 1},
                request_checksum_calculation="when_required",
                response_checksum_validation="when_required",
            ),
        )

    def store(self, object_key: str, content: bytes, mime_type: str) -> None:
        try:
            self.client.put_object(
                Bucket=self.bucket,
                Key=object_key,
                Body=content,
                ContentType=mime_type,
                ACL="private",
            )
        except (BotoCoreError, ClientError) as exc:
            raise PhotoStorageError("photo storage failed") from exc

    def delete(self, object_key: str) -> None:
        try:
            # S3 DELETE also succeeds when the object is already absent.
            self.client.delete_object(Bucket=self.bucket, Key=object_key)
        except (BotoCoreError, ClientError) as exc:
            raise PhotoStorageError("photo cleanup failed") from exc

    def create_read_url(self, object_key: str, expires_in: timedelta) -> str:
        try:
            return self.client.generate_presigned_url(
                "get_object",
                Params={"Bucket": self.bucket, "Key": object_key},
                ExpiresIn=int(expires_in.total_seconds()),
                HttpMethod="GET",
            )
        except (BotoCoreError, ClientError) as exc:
            raise PhotoStorageError("temporary photo URL generation failed") from exc

    def list_photos(self) -> Iterator[StoredPhoto]:
        try:
            pages = self.client.get_paginator("list_objects_v2").paginate(
                Bucket=self.bucket,
                Prefix="reports/",
            )
            for page in pages:
                for item in page.get("Contents", []):
                    yield StoredPhoto(
                        object_key=item["Key"], modified_at=item["LastModified"]
                    )
        except (BotoCoreError, ClientError) as exc:
            raise PhotoStorageError("photo listing failed") from exc
