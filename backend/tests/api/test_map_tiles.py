from uuid import UUID

from fastapi.testclient import TestClient

from app.api.dependencies.auth import get_current_identity
from app.main import app
from app.domain.report import ReportCategory


def verified_identity():
    return {"uid": "firebase-user-123", "email_verified": True}


def test_map_tile_returns_authenticated_vector_tile(monkeypatch):
    expected_tile = b"vector tile bytes"
    received = {}

    class FakeTileRepository:
        def get_tile(self, **kwargs):
            received.update(kwargs)
            return expected_tile

    monkeypatch.setattr(
        "app.api.routes.map_tiles.PostgreSQLMapTileRepository",
        FakeTileRepository,
    )
    app.dependency_overrides[get_current_identity] = verified_identity

    try:
        response = TestClient(app).get(
            "/api/v1/map/tiles/4/8/6.mvt",
            params={
                "category": "pollution",
                "report_id": "550e8400-e29b-41d4-a716-446655440000",
            },
        )
    finally:
        app.dependency_overrides.clear()

    assert response.status_code == 200
    assert response.content == expected_tile
    assert response.headers["content-type"] == "application/vnd.mapbox-vector-tile"
    assert response.headers["cache-control"] == "private, max-age=15, must-revalidate"
    assert received == {
        "zoom": 4,
        "x": 8,
        "y": 6,
        "category": ReportCategory.POLLUTION,
        "report_id": UUID("550e8400-e29b-41d4-a716-446655440000"),
    }


def test_map_tile_rejects_coordinates_outside_zoom():
    app.dependency_overrides[get_current_identity] = verified_identity

    try:
        response = TestClient(app).get("/api/v1/map/tiles/2/4/0.mvt")
    finally:
        app.dependency_overrides.clear()

    assert response.status_code == 422


def test_map_tile_requires_authentication():
    response = TestClient(app).get("/api/v1/map/tiles/0/0/0.mvt")

    assert response.status_code == 401


def test_bathymetry_tile_is_public_png(monkeypatch):
    expected_tile = b"fake png bytes"

    monkeypatch.setattr(
        "app.api.routes.map_tiles.fetch_bathymetry_tile",
        lambda z, x, y: expected_tile,
    )

    response = TestClient(app).get(
        "/api/v1/map/bathymetry/8/131/94.png"
    )

    assert response.status_code == 200
    assert response.content == expected_tile
    assert response.headers["content-type"] == "image/png"
    assert response.headers["cache-control"] == "public, max-age=86400"


def test_bathymetry_tile_rejects_coordinates_outside_zoom():
    response = TestClient(app).get(
        "/api/v1/map/bathymetry/2/4/0.png"
    )

    assert response.status_code == 422


def test_bathymetry_tile_returns_503_when_provider_is_unavailable(
    monkeypatch,
):
    from app.infrastructure.adapters.emodnet_bathymetry import (
        BathymetryUnavailable,
    )

    def fail(z, x, y):
        raise BathymetryUnavailable("test")

    monkeypatch.setattr(
        "app.api.routes.map_tiles.fetch_bathymetry_tile",
        fail,
    )

    response = TestClient(app).get(
        "/api/v1/map/bathymetry/8/131/94.png"
    )

    assert response.status_code == 503
