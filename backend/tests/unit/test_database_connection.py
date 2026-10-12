from unittest.mock import MagicMock

import psycopg
import pytest
from fastapi import Depends, FastAPI
from fastapi.testclient import TestClient
from psycopg_pool import PoolTimeout

from app.config.settings import Settings, get_settings
from app.dependencies.container import get_database_connection
from app.infrastructure.database import connection as database


@pytest.fixture
def pool(monkeypatch):
    pool = MagicMock()
    pool.connection.return_value.__enter__.return_value = MagicMock()
    monkeypatch.setattr(database, "get_database_pool", lambda settings=None: pool)
    return pool


def test_connection_context_receives_failure_for_rollback(pool):
    error = RuntimeError("operation failed")
    with pytest.raises(RuntimeError, match="operation failed"):
        with database.database_connection():
            raise error

    args = pool.connection.return_value.__exit__.call_args.args
    assert args[:2] == (RuntimeError, error)


def test_pool_failure_propagates(pool):
    pool.connection.return_value.__enter__.side_effect = psycopg.OperationalError(
        "unavailable"
    )
    with pytest.raises(psycopg.OperationalError):
        with database.database_connection():
            pytest.fail("No connection should be yielded")


def test_pool_is_bounded_and_shared_per_database_url(monkeypatch):
    created = []

    def make_pool(**kwargs):
        result = MagicMock()
        created.append((kwargs, result))
        return result

    monkeypatch.setattr(make_pool, "check_connection", MagicMock(), raising=False)
    monkeypatch.setattr(database, "ConnectionPool", make_pool)
    settings = Settings(database_url="postgresql://localhost/pool-test")
    try:
        first = database.get_database_pool(settings)
        assert database.get_database_pool(settings) is first
        assert len(created) == 1
        kwargs, _ = created[0]
        assert kwargs["min_size"] == 1
        assert kwargs["max_size"] == 15
        assert kwargs["timeout"] == 3
        assert kwargs["kwargs"] == {"connect_timeout": 3}
        assert kwargs["check"] is make_pool.check_connection
        first.open.assert_called_once()
    finally:
        database.close_database_pools()
    first.close.assert_called_once()


@pytest.mark.parametrize("result, expected", [((1,), True), ((0,), False), (None, False)])
def test_database_probe_uses_pool(pool, result, expected, monkeypatch):
    monkeypatch.setenv("DATABASE_URL", "postgresql://localhost/test")
    connection = pool.connection.return_value.__enter__.return_value
    cursor = connection.cursor.return_value.__enter__.return_value
    cursor.fetchone.return_value = result

    assert database.check_database_connection() is expected
    cursor.execute.assert_called_once_with("SELECT 1")
    pool.connection.return_value.__exit__.assert_called_once_with(None, None, None)


@pytest.mark.parametrize("fail", [False, True])
def test_injected_connection_rolls_back_before_return(pool, fail):
    app = FastAPI()
    settings = Settings(database_url="postgresql://localhost/test")
    app.dependency_overrides[get_settings] = lambda: settings
    connection = pool.connection.return_value.__enter__.return_value

    @app.get("/probe")
    def probe(connection=Depends(get_database_connection)):
        if fail:
            raise RuntimeError("request failed")
        return {"ok": True}

    with TestClient(app, raise_server_exceptions=False) as client:
        response = client.get("/probe")
    assert response.status_code == (500 if fail else 200)
    connection.rollback.assert_called_once()


def test_pool_timeout_is_reported_as_service_unavailable(pool):
    from app.api.dependencies.auth import get_current_identity
    from app.main import app

    pool.connection.return_value.__enter__.side_effect = PoolTimeout("unavailable")
    app.dependency_overrides[get_current_identity] = lambda: {
        "uid": "user", "email_verified": True
    }
    try:
        with TestClient(app, raise_server_exceptions=False) as client:
            response = client.get("/api/v1/map/tiles/0/0/0.mvt")
    finally:
        app.dependency_overrides.clear()

    assert response.status_code == 503
    assert response.json()["error"]["code"] == "dependency_unavailable"
