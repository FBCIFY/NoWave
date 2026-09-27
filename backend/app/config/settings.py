"""Configuration issue de l'environnement, validée lors d'une opération en base."""

import os
from dataclasses import dataclass, field
from pathlib import Path


class ConfigurationError(RuntimeError):
    """Un paramètre requis pour le backend est absent."""


@dataclass(frozen=True)
class Settings:
    database_url: str | None = field(default=None, repr=False)

    def require_database_url(self) -> str:
        if not self.database_url or not self.database_url.strip():
            raise ConfigurationError("DATABASE_URL must be set for database operations")
        return self.database_url


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
    return Settings(database_url=url)
