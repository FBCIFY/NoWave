from app.api.router import router
from app.main import app


def test_api_router_has_v1_prefix():
    assert router.prefix == "/api/v1"


def test_user_routes_are_registered():
    paths = app.openapi()["paths"]

    user_routes = paths["/api/v1/users/me"]

    assert "post" in user_routes
    assert "get" in user_routes
    assert "patch" in user_routes
    assert "delete" in user_routes
