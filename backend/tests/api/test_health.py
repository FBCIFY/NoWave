from unittest.mock import MagicMock, Mock

import psycopg
import pytest
from fastapi.testclient import TestClient
from psycopg_pool import PoolTimeout

from app.dependencies import container
from app.infrastructure.database import connection as database
from app.main import app

client = TestClient(app)


@pytest.fixture(autouse=True)
def forbid_database_connections(monkeypatch):
    connect = Mock(side_effect=AssertionError("Health tests must not connect to PostgreSQL"))
    monkeypatch.setattr(psycopg, "connect", connect)
    monkeypatch.setattr(psycopg.Connection, "connect", connect)
    yield
    connect.assert_not_called()


@pytest.mark.parametrize("configured", [True, False])
def test_health_endpoint_does_not_access_database(monkeypatch, configured):
    monkeypatch.delenv("DATABASE_URL_FILE", raising=False)
    if configured:
        monkeypatch.setenv("DATABASE_URL", "postgresql://localhost/test")
    else:
        monkeypatch.delenv("DATABASE_URL", raising=False)
    get_pool = Mock(side_effect=AssertionError("Liveness must not access the database pool"))
    monkeypatch.setattr(database, "get_database_pool", get_pool)
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}
    get_pool.assert_not_called()


@pytest.mark.parametrize("available", [True, False])
def test_readiness_endpoint(monkeypatch, available):
    check = Mock(return_value=available)
    monkeypatch.setattr(container, "check_database_connection", check)
    response = client.get("/health/ready")
    assert response.status_code == (200 if available else 503)
    assert response.json() == (
        {"status": "ready", "database": "ok"} if available
        else {"status": "not_ready", "database": "unavailable"}
    )
    check.assert_called_once()


@pytest.mark.parametrize("error_type", [psycopg.OperationalError, PoolTimeout])
def test_readiness_database_error(monkeypatch, error_type):
    monkeypatch.delenv("DATABASE_URL_FILE", raising=False)
    monkeypatch.setenv("DATABASE_URL", "postgresql://localhost/test")
    pool = MagicMock()
    pool.connection.return_value.__enter__.side_effect = error_type("private detail")
    get_pool = Mock(return_value=pool)
    monkeypatch.setattr(database, "get_database_pool", get_pool)

    response = client.get("/health/ready")

    assert response.status_code == 503
    assert response.json() == {"status": "not_ready", "database": "unavailable"}
    get_pool.assert_called_once()
    pool.connection.assert_called_once_with()
    pool.connection.return_value.__enter__.assert_called_once_with()


def test_readiness_without_database_configuration(monkeypatch):
    monkeypatch.delenv("DATABASE_URL", raising=False)
    monkeypatch.delenv("DATABASE_URL_FILE", raising=False)
    create_pool = Mock(side_effect=AssertionError("Missing configuration must fail before creating a pool"))
    monkeypatch.setattr(database, "ConnectionPool", create_pool)
    response = client.get("/health/ready")
    assert response.status_code == 503
    assert response.json() == {"status": "not_ready", "database": "unavailable"}
    create_pool.assert_not_called()


@pytest.mark.parametrize("path", ["/api/v1/health", "/api/v1/health/ready"])
def test_health_is_not_versioned(path):
    assert client.get(path).status_code == 404
