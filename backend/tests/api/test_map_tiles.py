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

    class Coast:
        async def get_mask(self, tile):
            assert (tile.z, tile.x, tile.y) == (8, 131, 94)
            return b"coastal mask"

    monkeypatch.setattr("app.api.routes.map_tiles.get_coastline_mask", lambda: Coast())
    monkeypatch.setattr("app.api.routes.map_tiles.has_raster_data", lambda raw: True)
    monkeypatch.setattr(
        "app.api.routes.map_tiles.apply_ocean_mask",
        lambda raw, mask: raw if mask == b"coastal mask" else b"invalid",
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


def test_coastline_failure_returns_503_instead_of_unmasked_png(monkeypatch):
    from app.domain.marine import ProviderUnavailable

    class Coast:
        async def get_mask(self, tile):
            raise ProviderUnavailable('coast offline')

    monkeypatch.setattr('app.api.routes.map_tiles.fetch_bathymetry_tile', lambda *args: b'raw')
    monkeypatch.setattr('app.api.routes.map_tiles.get_coastline_mask', lambda: Coast())
    monkeypatch.setattr('app.api.routes.map_tiles.has_raster_data', lambda raw: True)
    response = TestClient(app).get('/api/v1/map/bathymetry/6/33/23.png')
    assert response.status_code == 503
    assert response.content != b'raw'


def test_transparent_bathymetry_does_not_download_a_coastline(monkeypatch):
    from io import BytesIO
    from PIL import Image

    output = BytesIO()
    Image.new('RGBA', (256, 256), (0, 0, 0, 0)).save(output, format='PNG')
    content = output.getvalue()
    monkeypatch.setattr('app.api.routes.map_tiles.fetch_bathymetry_tile', lambda *args: content)

    def forbidden():
        raise AssertionError('unnecessary coastline request')

    monkeypatch.setattr('app.api.routes.map_tiles.get_coastline_mask', forbidden)
    response = TestClient(app).get('/api/v1/map/bathymetry/6/33/23.png')
    assert response.status_code == 200 and response.content == content
