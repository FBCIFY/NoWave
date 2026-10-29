"""Exercise pooled connections against an isolated migrated PostgreSQL database."""

from uuid import uuid4

import psycopg
import pytest

from app.config.settings import Settings
from app.infrastructure.database.connection import (
    close_database_pools,
    database_connection,
    get_database_pool,
)


@pytest.fixture
def settings(dsn):
    # Other repository tests may have grown the shared pool for this test DSN.
    close_database_pools()
    settings = Settings(database_url=dsn)
    yield settings
    close_database_pools()


def test_reuses_a_database_session(settings):
    get_database_pool(settings).wait()
    with database_connection(settings) as connection:
        first_pid = connection.execute("SELECT pg_backend_pid()").fetchone()[0]
    with database_connection(settings) as connection:
        second_pid = connection.execute("SELECT pg_backend_pid()").fetchone()[0]

    assert second_pid == first_pid


def test_failure_rolls_back_and_set_local_does_not_leak(settings):
    user_id = uuid4()
    with database_connection(settings) as connection:
        baseline = connection.execute("SHOW lock_timeout").fetchone()[0]

    with pytest.raises(RuntimeError, match="abort this operation"):
        with database_connection(settings) as connection:
            connection.execute("SET LOCAL lock_timeout = '3s'")
            connection.execute(
                """
                INSERT INTO nowave.users
                    (id, firebase_uid, username, email, role, status,
                     created_at, updated_at)
                VALUES (%s, %s, %s, %s, 'user', 'active', now(), now())
                """,
                (user_id, str(user_id), str(user_id), f"{user_id}@nowave.test"),
            )
            raise RuntimeError("abort this operation")

    with database_connection(settings) as connection:
        assert connection.execute("SHOW lock_timeout").fetchone()[0] == baseline
        assert connection.execute(
            "SELECT count(*) FROM nowave.users WHERE id = %s", (user_id,)
        ).fetchone()[0] == 0

    with database_connection(settings, transactional=False) as connection:
        connection.execute("SET LOCAL lock_timeout = '3s'")
    with database_connection(settings) as connection:
        assert connection.execute("SHOW lock_timeout").fetchone()[0] == baseline


def test_replaces_a_connection_killed_while_idle(settings):
    get_database_pool(settings).wait()
    with database_connection(settings) as connection:
        first_pid = connection.execute("SELECT pg_backend_pid()").fetchone()[0]

    with psycopg.connect(settings.database_url, autocommit=True) as admin:
        assert admin.execute(
            "SELECT pg_terminate_backend(%s)", (first_pid,)
        ).fetchone()[0]

    with database_connection(settings) as connection:
        replacement_pid = connection.execute("SELECT pg_backend_pid()").fetchone()[0]
    assert replacement_pid != first_pid
