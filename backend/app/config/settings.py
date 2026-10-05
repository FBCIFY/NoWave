"""Configuration issue de l'environnement, validée lors d'une opération en base."""

import os
from dataclasses import dataclass, field
from pathlib import Path


class ConfigurationError(RuntimeError):
    """Un paramètre requis pour le backend est absent."""


def read_secret(name: str) -> str | None:
    value = os.getenv(name)
    filename = os.getenv(f"{name}_FILE")
    if value and filename:
        raise ConfigurationError(f"Set {name} or {name}_FILE, not both")
    if filename:
        try:
            value = Path(filename).read_text().strip()
        except OSError:
            raise ConfigurationError(f"{name}_FILE cannot be read") from None
    return value


@dataclass(frozen=True)
class PhotoStorageSettings:
    bucket: str
    region: str
    access_key: str = field(repr=False)
    secret_key: str = field(repr=False)

    @property
    def endpoint_url(self) -> str:
        return f"https://s3.{self.region}.scw.cloud"


@dataclass(frozen=True)
class Settings:
    database_url: str | None = field(default=None, repr=False)
    photo_storage_bucket: str | None = None
    photo_storage_region: str = "fr-par"
    scaleway_access_key: str | None = field(default=None, repr=False)
    scaleway_secret_key: str | None = field(default=None, repr=False)

    def require_database_url(self) -> str:
        if not self.database_url or not self.database_url.strip():
            raise ConfigurationError("DATABASE_URL must be set for database operations")
        return self.database_url

    def require_photo_storage_bucket(self) -> str:
        if not self.photo_storage_bucket or not self.photo_storage_bucket.strip():
            raise ConfigurationError(
                "PHOTO_STORAGE_BUCKET must be set for photo operations"
            )
        return self.photo_storage_bucket.strip()

    def require_photo_storage(self) -> PhotoStorageSettings:
        bucket = self.require_photo_storage_bucket()
        if self.photo_storage_region not in {"fr-par", "nl-ams", "pl-waw"}:
            raise ConfigurationError(
                "PHOTO_STORAGE_REGION must be a supported Scaleway region"
            )
        if not self.scaleway_access_key or not self.scaleway_access_key.strip():
            raise ConfigurationError("SCW_ACCESS_KEY must be set for photo operations")
        if not self.scaleway_secret_key or not self.scaleway_secret_key.strip():
            raise ConfigurationError("SCW_SECRET_KEY must be set for photo operations")
        return PhotoStorageSettings(
            bucket=bucket,
            region=self.photo_storage_region,
            access_key=self.scaleway_access_key.strip(),
            secret_key=self.scaleway_secret_key.strip(),
        )


def get_settings() -> Settings:
    url = os.getenv("DATABASE_URL")
    filename = os.getenv("DATABASE_URL_FILE")
    if url and filename:
        raise ConfigurationError("Set DATABASE_URL or DATABASE_URL_FILE, not both")
    if filename:
        try:
            url = Path(filename).read_text().strip()
        except OSError:
            raise ConfigurationError("DATABASE_URL_FILE cannot be read") from None
    return Settings(
        database_url=url,
        photo_storage_bucket=os.getenv("PHOTO_STORAGE_BUCKET"),
        photo_storage_region=os.getenv("PHOTO_STORAGE_REGION", "fr-par"),
        scaleway_access_key=read_secret("SCW_ACCESS_KEY"),
        scaleway_secret_key=read_secret("SCW_SECRET_KEY"),
    )
