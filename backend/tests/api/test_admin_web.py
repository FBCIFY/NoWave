import psycopg
import pytest
from fastapi.testclient import TestClient
from starlette.requests import Request

from app.config.settings import ConfigurationError
from app.dependencies.admin_web_session import get_admin_web_session
from app.domain.errors import (
    AdminRequiredError,
    EmailNotVerifiedError,
    InactiveUserError,
    InvalidCredentialsError,
    InvalidSessionError,
    SignInUnavailableError,
    UserNotFoundError,
)
from app.domain.user import User, UserRole, UserStatus
from app.main import app
from app.web.csrf import CSRF_COOKIE, session_csrf_token
from app.web.errors import SESSION_COOKIE, WebCsrfRejected, WebLoginRequired
from app.web.security import AdminSecurity


ADMIN = User(
    firebase_uid="firebase-admin-1",
    username="admin",
    email="admin@nowave.test",
    role=UserRole.ADMIN,
)


class FakeAdminWebSession:
    def __init__(self, sign_in_error=None, session_error=None, admin=ADMIN):
        self.sign_in_error = sign_in_error
        self.session_error = session_error
        self.admin = admin
        self.sign_ins = []

    def sign_in(self, email, password):
        self.sign_ins.append((email, password))
        if self.sign_in_error:
            raise self.sign_in_error
        return "session-cookie"

    def authenticate(self, session_cookie):
        if self.session_error:
            raise self.session_error
        if session_cookie != "session-cookie":
            raise InvalidSessionError("invalid admin session")
        return self.admin


@pytest.fixture
def web_session():
    session = FakeAdminWebSession()
    app.dependency_overrides[get_admin_web_session] = lambda: session
    yield session
    app.dependency_overrides.clear()


@pytest.fixture
def client():
    # __Host- cookies are Secure: the browser only sends them over HTTPS.
    return TestClient(app, base_url="https://testserver")


def set_cookie_headers(response):
    return response.headers.get_list("set-cookie")


def cookie_header(response, name):
    return next(
        header
        for header in set_cookie_headers(response)
        if header.startswith(f"{name}=")
    )


def login_form(client):
    response = client.get("/admin/login")
    return response, client.cookies.get(CSRF_COOKIE)


def submit_login(client, csrf_token, email="admin@nowave.test", password="secret"):
    return client.post(
        "/admin/login",
        data={"email": email, "password": password, "csrf_token": csrf_token},
        follow_redirects=False,
    )


def sign_in(client):
    _, token = login_form(client)
    return submit_login(client, token)


def test_login_page_sets_csrf_cookie_and_field(client, web_session):
    response, token = login_form(client)

    assert response.status_code == 200
    assert response.headers["cache-control"] == "no-store"
    assert f'name="csrf_token" value="{token}"' in response.text
    assert "<script" not in response.text

    header = cookie_header(response, CSRF_COOKIE)
    for flag in ("HttpOnly", "Secure", "SameSite=strict", "Path=/"):
        assert flag in header


def test_login_creates_secure_session(client, web_session):
    _, token = login_form(client)

    response = submit_login(client, token)

    assert response.status_code == 303
    assert response.headers["location"] == "/admin"
    assert web_session.sign_ins == [("admin@nowave.test", "secret")]

    header = cookie_header(response, SESSION_COOKIE)
    assert header.startswith(f"{SESSION_COOKIE}=session-cookie;")
    for flag in (
        "HttpOnly",
        "Secure",
        "SameSite=strict",
        "Path=/",
        "Max-Age=28800",
    ):
        assert flag in header

    # Signed-in forms use the session token: the login one is dropped.
    assert "Max-Age=0" in cookie_header(response, CSRF_COOKIE)


@pytest.mark.parametrize("csrf_token", ["", "forged-token"])
def test_forged_login_is_rejected_before_sign_in(client, web_session, csrf_token):
    login_form(client)

    response = submit_login(client, csrf_token)

    assert response.status_code == 403
    assert "Formulaire expiré" in response.text
    assert web_session.sign_ins == []


def test_login_without_csrf_cookie_is_rejected(client, web_session):
    response = submit_login(client, "any-token")

    assert response.status_code == 403
    assert web_session.sign_ins == []


@pytest.mark.parametrize(
    ("error", "status_code", "message"),
    [
        (
            InvalidCredentialsError("invalid email or password"),
            401,
            "E-mail ou mot de passe incorrect.",
        ),
        (
            AdminRequiredError("an active administrator is required"),
            403,
            "accès à l&#39;administration",
        ),
        (
            InactiveUserError("user is not active"),
            403,
            "accès à l&#39;administration",
        ),
        (
            EmailNotVerifiedError("email must be verified"),
            403,
            "accès à l&#39;administration",
        ),
        (
            UserNotFoundError("user profile not found"),
            403,
            "accès à l&#39;administration",
        ),
        (
            SignInUnavailableError("sign-in service unavailable"),
            503,
            "momentanément impossible",
        ),
        (
            psycopg.OperationalError("connection to db.internal failed"),
            503,
            "momentanément impossible",
        ),
        (
            ConfigurationError("FIREBASE_WEB_API_KEY must be set"),
            503,
            "momentanément impossible",
        ),
    ],
)
def test_refused_login_creates_no_session(
    client,
    web_session,
    error,
    status_code,
    message,
):
    web_session.sign_in_error = error
    _, token = login_form(client)

    response = submit_login(client, token)

    assert response.status_code == status_code
    assert message in response.text
    assert "db.internal" not in response.text
    assert "FIREBASE_WEB_API_KEY" not in response.text
    assert SESSION_COOKIE not in response.headers.get("set-cookie", "")
    # The typed email is kept, the password never comes back.
    assert 'value="admin@nowave.test"' in response.text
    assert "secret" not in response.text


def test_empty_login_form_is_rejected(client, web_session):
    _, token = login_form(client)

    response = submit_login(client, token, email="  ", password="")

    assert response.status_code == 400
    assert web_session.sign_ins == []


def test_home_requires_session(client, web_session):
    response = client.get("/admin", follow_redirects=False)

    assert response.status_code == 303
    assert response.headers["location"] == "/admin/login"
    # A link from another site arrives without the SameSite=Strict
    # cookie: the session of the other tabs must not be deleted.
    assert "set-cookie" not in response.headers


def test_trailing_slash_redirect_stays_relative(client, web_session):
    response = client.get("/admin/", follow_redirects=False)

    assert response.status_code == 308
    assert response.headers["location"] == "/admin"


def test_home_shows_active_admin(client, web_session):
    sign_in(client)

    response = client.get("/admin")

    assert response.status_code == 200
    assert response.headers["cache-control"] == "no-store"
    assert "Bonjour admin" in response.text
    assert 'action="/admin/logout"' in response.text
    token = session_csrf_token("session-cookie")
    assert f'name="csrf_token" value="{token}"' in response.text
    # The page does not set a login token again.
    assert CSRF_COOKIE not in response.headers.get("set-cookie", "")


def test_invalid_session_redirects_and_clears_cookie(client, web_session):
    client.cookies.set(SESSION_COOKIE, "forged-cookie")

    response = client.get("/admin", follow_redirects=False)

    assert response.status_code == 303
    assert response.headers["location"] == "/admin/login"
    assert 'Max-Age=0' in cookie_header(response, SESSION_COOKIE)


def test_admin_suspended_after_sign_in_loses_access(client, web_session):
    sign_in(client)
    web_session.session_error = InactiveUserError("user is not active")

    response = client.get("/admin", follow_redirects=False)

    assert response.status_code == 403
    assert "Accès refusé" in response.text
    assert 'Max-Age=0' in cookie_header(response, SESSION_COOKIE)


def test_ordinary_user_session_is_refused(client, web_session):
    sign_in(client)
    web_session.session_error = AdminRequiredError(
        "an active administrator is required"
    )

    response = client.get("/admin", follow_redirects=False)

    assert response.status_code == 403


def test_session_check_outage_returns_503(client, web_session):
    sign_in(client)
    web_session.session_error = SignInUnavailableError(
        "sign-in service unavailable"
    )

    response = client.get("/admin", follow_redirects=False)

    assert response.status_code == 503
    assert "Service indisponible" in response.text


def test_logout_clears_cookies(client, web_session):
    sign_in(client)

    response = client.post(
        "/admin/logout",
        data={"csrf_token": session_csrf_token("session-cookie")},
        follow_redirects=False,
    )

    assert response.status_code == 303
    assert response.headers["location"] == "/admin/login"
    assert response.headers["cache-control"] == "no-store"
    assert 'Max-Age=0' in cookie_header(response, SESSION_COOKIE)
    assert 'Max-Age=0' in cookie_header(response, CSRF_COOKIE)
    assert client.get("/admin", follow_redirects=False).status_code == 303


@pytest.mark.parametrize(
    "csrf_token",
    [
        "",
        "forged-token",
        # Valid token, but of another session.
        session_csrf_token("other-session-cookie"),
    ],
)
def test_forged_logout_is_rejected(client, web_session, csrf_token):
    sign_in(client)

    response = client.post(
        "/admin/logout",
        data={"csrf_token": csrf_token},
        follow_redirects=False,
    )

    assert response.status_code == 403
    assert "Formulaire expiré" in response.text
    assert client.get("/admin").status_code == 200


def test_login_form_token_cannot_log_out(client, web_session):
    _, login_token = login_form(client)
    sign_in(client)

    response = client.post(
        "/admin/logout",
        data={"csrf_token": login_token},
        follow_redirects=False,
    )

    assert response.status_code == 403


def test_logout_without_session_goes_to_login(client, web_session):
    response = client.post(
        "/admin/logout",
        data={"csrf_token": "any-token"},
        follow_redirects=False,
    )

    assert response.status_code == 303
    assert response.headers["location"] == "/admin/login"


def test_session_csrf_token_is_bound_to_the_session():
    token = session_csrf_token("session-cookie")

    assert token == session_csrf_token("session-cookie")
    assert token != session_csrf_token("next-session-cookie")


def request_with_session(session_cookie):
    headers = []
    if session_cookie:
        headers.append(
            (b"cookie", f"{SESSION_COOKIE}={session_cookie}".encode())
        )
    return Request({"type": "http", "method": "GET", "headers": headers})


def test_admin_security_builds_context_from_session():
    security = AdminSecurity(FakeAdminWebSession())
    request = request_with_session("session-cookie")

    context = security.require_active_admin(request)

    assert context.subject is ADMIN
    assert context.csrf_token == session_csrf_token("session-cookie")
    security.verify_csrf(request, context, context.csrf_token)

    with pytest.raises(WebCsrfRejected):
        security.verify_csrf(request, context, "forged-token")


def test_admin_security_requires_session():
    security = AdminSecurity(FakeAdminWebSession())

    with pytest.raises(WebLoginRequired):
        security.require_active_admin(request_with_session(None))


def test_username_is_escaped(client, web_session):
    web_session.admin = User(
        firebase_uid="firebase-admin-1",
        username="<script>alert(1)</script>",
        email="admin@nowave.test",
        role=UserRole.ADMIN,
        status=UserStatus.ACTIVE,
    )
    sign_in(client)

    response = client.get("/admin")

    assert "<script>" not in response.text
    assert "&lt;script&gt;" in response.text


def test_admin_pages_are_not_in_openapi(client):
    paths = client.get("/openapi.json").json()["paths"]

    assert not any(path.startswith("/admin") for path in paths)
