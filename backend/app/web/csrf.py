import hashlib
import secrets

from fastapi import Request
from starlette.responses import Response

from app.web.errors import WebCsrfRejected


# Before sign-in there is no session to bind a token to: the login form
# uses a random token held in this cookie (double submit). The __Host-
# prefix makes the browser refuse the cookie unless it is Secure, on
# Path=/ and without Domain, so a subdomain cannot set it.
CSRF_COOKIE = "__Host-nowave_admin_csrf"

# Separates this hash from any other use of the session cookie.
SESSION_CSRF_LABEL = b"nowave-admin-csrf:"


def login_csrf_token(request: Request) -> str:
    """Token for the hidden field of the login form."""
    return request.cookies.get(CSRF_COOKIE) or secrets.token_urlsafe(32)


def set_csrf_cookie(response: Response, token: str) -> None:
    response.set_cookie(
        CSRF_COOKIE,
        token,
        httponly=True,
        secure=True,
        samesite="strict",
        path="/",
    )


def delete_csrf_cookie(response: Response) -> None:
    response.delete_cookie(
        CSRF_COOKIE,
        path="/",
        secure=True,
        httponly=True,
        samesite="strict",
    )


def check_login_csrf(request: Request, submitted: str) -> None:
    """Double submit: the form field must match the cookie. Another site
    can make the browser send the cookie, but it cannot read it."""
    expected = request.cookies.get(CSRF_COOKIE)

    if not expected:
        raise WebCsrfRejected()

    check_token(expected, submitted)


def session_csrf_token(session_cookie: str) -> str:
    """Token of the signed-in forms, computed by the server from the
    session cookie: a new session gives a new token, and it is useless
    once the session ends. The hash does not reveal the cookie."""
    return hashlib.sha256(
        SESSION_CSRF_LABEL + session_cookie.encode()
    ).hexdigest()


def check_token(expected: str, submitted: str) -> None:
    """Constant-time comparison, so timing does not leak the token."""
    if not submitted:
        raise WebCsrfRejected()

    if not secrets.compare_digest(
        expected.encode(),
        submitted.encode(),
    ):
        raise WebCsrfRejected()
