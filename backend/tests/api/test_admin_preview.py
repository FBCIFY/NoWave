"""Keep Safari's HTTP preview usable without changing production security."""
import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.dependencies.admin_web_session import get_admin_web_session
from app.domain.errors import InvalidCredentialsError, InvalidSessionError
from app.domain.user import User, UserRole
from app.web.csrf import session_csrf_token
from app.web.errors import register_web_error_handlers
from app.web.routes.admin_pages import router
from tests.browser.preview import PreviewCookiesMiddleware

CSRF = "nowave_preview_admin_csrf"
SESSION = "nowave_preview_admin_session"


class PreviewSession:
    sign_ins = 0

    def sign_in(self, email, password):
        self.sign_ins += 1
        if (email, password) != ("admin@nowave.test", "preview-only"):
            raise InvalidCredentialsError()
        return "synthetic-session"

    def authenticate(self, value):
        if value != "synthetic-session":
            raise InvalidSessionError()
        return User(firebase_uid="preview", username="Preview", email="admin@nowave.test", role=UserRole.ADMIN)


@pytest.fixture
def preview():
    app = FastAPI()
    app.include_router(router)
    register_web_error_handlers(app)
    session = PreviewSession()
    app.dependency_overrides[get_admin_web_session] = lambda: session
    app.add_middleware(PreviewCookiesMiddleware)
    with TestClient(app, base_url="http://127.0.0.1:5173") as client:
        yield client, session


def login(client, token):
    return client.post("/admin/login", data={"email": "admin@nowave.test", "password": "preview-only", "csrf_token": token}, follow_redirects=False)


def test_http_preview_login_and_logout_preserve_auth_csrf_and_cookie_flags(preview):
    client, session = preview
    form = client.get("/admin/login")
    token = client.cookies.get(CSRF)
    assert token and f'value="{token}"' in form.text
    cookie = form.headers["set-cookie"]
    assert cookie.startswith(CSRF + "=")
    assert "Secure" not in cookie and "__Host-" not in cookie
    assert "HttpOnly" in cookie and "SameSite=strict" in cookie and "Path=/" in cookie
    response = login(client, token)
    assert response.status_code == 303 and response.headers["location"] == "/admin"
    assert client.cookies.get(SESSION) == "synthetic-session"
    assert client.cookies.get(CSRF) is None
    assert client.get("/admin").status_code == 200
    assert session.sign_ins == 1
    forged = client.post("/admin/logout", data={"csrf_token": "forged"}, follow_redirects=False)
    assert forged.status_code == 403
    assert client.get("/admin").status_code == 200
    signed_out = client.post("/admin/logout", data={"csrf_token": session_csrf_token("synthetic-session")}, follow_redirects=False)
    assert signed_out.status_code == 303
    assert client.cookies.get(SESSION) is None
    assert client.get("/admin", follow_redirects=False).status_code == 303


@pytest.mark.parametrize("mode", ["missing-cookie", "forged-token", "missing-token", "production-cookie"])
def test_preview_rejects_forged_login_before_authentication(preview, mode):
    client, session = preview
    client.get("/admin/login")
    token = client.cookies.get(CSRF)
    if mode in {"missing-cookie", "production-cookie"}:
        client.cookies.clear()
    if mode == "production-cookie":
        client.cookies.set("__Host-nowave_admin_csrf", token)
    if mode == "forged-token":
        token = "forged"
    if mode == "missing-token":
        token = ""
    assert login(client, token).status_code == 403
    assert session.sign_ins == 0


def test_preview_rejects_unknown_session_and_non_loopback_host(preview):
    client, _ = preview
    client.cookies.set(SESSION, "expired-preview-session")
    response = client.get("/admin", follow_redirects=False)
    assert response.status_code == 303
    assert any(SESSION in value and "Max-Age=0" in value for value in response.headers.get_list("set-cookie"))
    external = client.get("/admin/login", headers={"Host": "example.com"})
    assert external.status_code == 403
    assert "set-cookie" not in external.headers
