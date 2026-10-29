import pytest
from fastapi.testclient import TestClient

from app.api.dependencies.auth import get_current_identity
from app.dependencies.admin_web_session import get_admin_web_session
from app.main import app


@pytest.fixture(autouse=True)
def forbid_private_dependencies(monkeypatch):
    def forbidden(*args, **kwargs):
        raise AssertionError("Public map config must not access private services")

    for target in (
        "app.infrastructure.database.connection.get_database_pool",
        "app.config.settings.get_settings",
    ):
        monkeypatch.setattr(target, forbidden)
    previous = app.dependency_overrides.copy()
    app.dependency_overrides[get_current_identity] = forbidden
    app.dependency_overrides[get_admin_web_session] = forbidden
    yield
    app.dependency_overrides.clear()
    app.dependency_overrides.update(previous)


def test_public_map_config_only_returns_browser_token(monkeypatch):
    token = "pk.eyJ1IjoidGVzdCJ9.public-browser-token"
    monkeypatch.setenv("MAPBOX_PUBLIC_TOKEN", f" {token} ")
    monkeypatch.setenv("DATABASE_URL", "private-database-url")
    monkeypatch.setenv("FIREBASE_WEB_API_KEY", "private-api-key")

    response = TestClient(app).get("/api/v1/map/web-config")

    assert response.status_code == 200
    assert response.json() == {"mapbox_token": token}
    assert response.headers["cache-control"] == "no-store"
    assert "set-cookie" not in response.headers


@pytest.mark.parametrize("token", [
    None, "", " ", "sk.payload.secret", "tk.payload.temporary", "pk.",
    "pk.incomplete", "pk.payload.signature<script>", "pk.payload.signature\nextra",
])
def test_missing_or_non_public_tokens_are_never_exposed(monkeypatch, token):
    if token is None:
        monkeypatch.delenv("MAPBOX_PUBLIC_TOKEN", raising=False)
    else:
        monkeypatch.setenv("MAPBOX_PUBLIC_TOKEN", token)

    response = TestClient(app).get("/api/v1/map/web-config")

    assert response.status_code == 200
    assert response.json() == {"mapbox_token": ""}
    assert response.headers["cache-control"] == "no-store"


@pytest.mark.parametrize("asset", [
    "mapbox-gl.js", "mapbox-gl.css", "maritime-style.js", "marker-icons.js",
])
def test_shared_map_assets_are_public_without_session(asset):
    response = TestClient(app).get(f"/admin-static/{asset}")

    assert response.status_code == 200
    assert response.content
    assert "set-cookie" not in response.headers
