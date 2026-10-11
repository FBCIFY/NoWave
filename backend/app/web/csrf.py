import secrets

from fastapi import Form, Request
from starlette.responses import Response

from app.web.errors import WebCsrfRejected


# The __Host- prefix makes the browser refuse the cookie unless it is
# Secure, on Path=/ and without Domain, so a subdomain cannot set it.
CSRF_COOKIE = "__Host-nowave_admin_csrf"
CSRF_FIELD = "csrf_token"


def csrf_token_for(request: Request) -> str:
    """Token to put in the hidden field of every admin form."""
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


def check_csrf(request: Request, submitted: str) -> None:
    """Double submit: the form field must match the cookie. Another site
    can make the browser send the cookie, but it cannot read it."""
    expected = request.cookies.get(CSRF_COOKIE)

    if not expected or not submitted:
        raise WebCsrfRejected()

    if not secrets.compare_digest(
        expected.encode(),
        submitted.encode(),
    ):
        raise WebCsrfRejected()


def require_csrf(
    request: Request,
    csrf_token: str = Form(""),
) -> None:
    """Dependency for every admin POST form."""
    check_csrf(request, csrf_token)
