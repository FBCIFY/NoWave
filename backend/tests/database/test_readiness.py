"""Vérifie le readiness et PostGIS avec une vraie base temporaire migrée."""

import psycopg
from fastapi.testclient import TestClient

from app.main import app


def test_ready_with_migrated_postgis_database(dsn, monkeypatch):
    monkeypatch.setenv("DATABASE_URL", dsn)
    with psycopg.connect(dsn) as connection:
        assert connection.execute("SELECT PostGIS_Version()").fetchone()[0]
        assert connection.execute(
            "SELECT ST_DWithin(ST_SetSRID(ST_MakePoint(5, 43), 4326)::geography, "
            "ST_SetSRID(ST_MakePoint(5, 43), 4326)::geography, 18520)"
        ).fetchone()[0]
    with TestClient(app) as client:
        response = client.get("/health/ready")
    assert response.status_code == 200
    assert response.json() == {"status": "ready", "database": "ok"}
