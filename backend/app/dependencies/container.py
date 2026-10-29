"""Point de liaison entre FastAPI et les dépendances d'infrastructure communes."""

from collections.abc import Iterator
from typing import Annotated

from fastapi import Depends
from psycopg import Connection, Error as PsycopgError

from app.config.settings import ConfigurationError, Settings, get_settings
from app.infrastructure.database.connection import (
    check_database_connection,
    database_connection,
)

SettingsDependency = Annotated[Settings, Depends(get_settings)]


def get_database_connection(settings: SettingsDependency) -> Iterator[Connection]:
    """Fournit une connexion aux futurs dépôts via Depends."""
    with database_connection(settings, transactional=False) as connection:
        yield connection


def get_database_ready(settings: SettingsDependency) -> bool:
    try:
        return check_database_connection(settings)
    except (PsycopgError, ConfigurationError):
        return False
