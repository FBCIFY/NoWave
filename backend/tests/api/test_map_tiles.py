from uuid import UUID

import pytest
from fastapi.testclient import TestClient

from app.api.dependencies.auth import get_current_identity
from app.main import app
from app.domain.report import ReportCategory
from app.infrastructure.marine.bathymetry_cache import BathymetryTileCache
from app.infrastructure.marine.coastline import CoastlineContext


@pytest.fixture(autouse=True)
def isolated_bathymetry_cache(tmp_path, monkeypatch):
    cache = None

    def get_cache(render):
        nonlocal cache
        if cache is None:
            cache = BathymetryTileCache(render, tmp_path / "bathymetry.sqlite3")
        return cache

    monkeypatch.setattr("app.api.routes.map_tiles.get_bathymetry_cache", get_cache)


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
        lambda z, x, y, padded: expected_tile,
    )

    class Coast:
        async def get_context(self, tile, raw):
            assert (tile.z, tile.x, tile.y) == (8, 131, 94)
            return CoastlineContext(b"coastal mask")

    monkeypatch.setattr("app.api.routes.map_tiles.get_coastline_mask", lambda: Coast())
    monkeypatch.setattr("app.api.routes.map_tiles.has_raster_data", lambda raw: True)
    monkeypatch.setattr(
        "app.api.routes.map_tiles.render_visual_water",
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

    def fail(z, x, y, padded):
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
        async def get_context(self, tile, raw):
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
    Image.new('RGBA', (280, 280), (0, 0, 0, 0)).save(output, format='PNG')
    content = output.getvalue()
    monkeypatch.setattr('app.api.routes.map_tiles.fetch_bathymetry_tile', lambda *args: content)

    def forbidden():
        raise AssertionError('unnecessary coastline request')

    monkeypatch.setattr('app.api.routes.map_tiles.get_coastline_mask', forbidden)
    response = TestClient(app).get('/api/v1/map/bathymetry/6/33/23.png')
    assert response.status_code == 200
    with Image.open(BytesIO(response.content)) as image:
        assert image.size == (256, 256)
        assert image.getchannel('A').getbbox() is None


def test_visual_continuity_keeps_original_coverage_and_shares_warm_requests(monkeypatch):
    import base64
    from io import BytesIO
    from PIL import Image

    raw = Image.new('RGBA', (280, 280), (40, 140, 160, 255))
    raw.paste((255, 255, 255, 0), (124, 124, 129, 129))
    output = BytesIO()
    raw.save(output, format='PNG')
    calls = []

    def fetch(z, x, y, padded):
        calls.append((z, x, y, padded))
        return output.getvalue()

    class Coast:
        async def get_context(self, tile, raw):
            return CoastlineContext(Image.new('L', (280, 280), 255))

    monkeypatch.setattr('app.api.routes.map_tiles.fetch_bathymetry_tile', fetch)
    monkeypatch.setattr('app.api.routes.map_tiles.get_coastline_mask', lambda: Coast())
    client = TestClient(app)
    first = client.get('/api/v1/map/bathymetry/14/8462/6014.png?v=marine-visual-7')
    second = client.get('/api/v1/map/bathymetry/14/8462/6014.png?v=marine-visual-7')
    assert first.status_code == second.status_code == 200
    assert first.content == second.content
    assert calls == [(14, 8462, 6014, True)]
    assert first.headers['x-nowave-raster-render'] == 'marine-visual-7'
    assert first.headers['x-nowave-raster-usage'] == 'visual-only; local-rgb-continuity'
    image = Image.open(BytesIO(first.content))
    assert image.getpixel((114, 114)) == (40, 140, 160, 255)
    coverage = base64.b64decode(image.info['NoWave.SourceCoverage'])
    assert coverage[114 * 256 + 114] == 0
