from collections.abc import Iterator
from contextlib import contextmanager
from threading import Lock

import psycopg
from psycopg_pool import ConnectionPool

from app.config.settings import Settings, get_settings


_pools: dict[str, ConnectionPool] = {}
_pools_lock = Lock()


def get_database_pool(settings: Settings | None = None) -> ConnectionPool:
    """Share a bounded pool for each database URL in this process."""
    settings = settings if settings is not None else get_settings()
    url = settings.require_database_url()
    with _pools_lock:
        pool = _pools.get(url)
        if pool is None:
            pool = ConnectionPool(
                conninfo=url,
                min_size=1,
                max_size=10,
                timeout=3,
                kwargs={"connect_timeout": 3},
                check=ConnectionPool.check_connection,
                open=False,
            )
            pool.open()
            _pools[url] = pool
        return pool


def close_database_pools() -> None:
    """Close the connections owned by this process at application shutdown."""
    with _pools_lock:
        pools = list(_pools.values())
        _pools.clear()
    for pool in pools:
        pool.close()


@contextmanager
def database_connection(
    settings: Settings | None = None, *, transactional: bool = True,
) -> Iterator[psycopg.Connection]:
    """Return a clean connection to the pool after each database operation."""
    with get_database_pool(settings).connection() as connection:
        if transactional:
            yield connection
        else:
            try:
                yield connection
            finally:
                # This dependency historically discarded uncommitted work on close.
                # An explicit rollback keeps that contract when the connection is reused.
                connection.rollback()


def check_database_connection(settings: Settings | None = None) -> bool:
    """Vérifie la réponse de PostgreSQL avec le cycle de connexion commun."""
    with database_connection(settings) as connection:
        with connection.cursor() as cursor:
            cursor.execute("SELECT 1")
            result = cursor.fetchone()

    return result == (1,)
