import psycopg
from fastapi import FastAPI, Request
from fastapi.responses import RedirectResponse

from app.config.settings import ConfigurationError
from app.web.templating import render


SESSION_COOKIE = "__Host-nowave_admin_session"
LOGIN_PATH = "/admin/login"

# Same list as the JSON 503 handler in app.main: their messages can hold
# hostnames or credentials, so the page never shows them.
DEPENDENCY_ERRORS = (
    psycopg.OperationalError,
    psycopg.InterfaceError,
    ConfigurationError,
)


class WebLoginRequired(Exception):
    pass


class WebAccessDenied(Exception):
    pass


class WebCsrfRejected(Exception):
    pass


class WebServiceUnavailable(Exception):
    pass


def delete_session_cookie(response) -> None:
    response.delete_cookie(
        SESSION_COOKIE,
        path="/",
        secure=True,
        httponly=True,
        samesite="strict",
    )


def login_required_handler(request: Request, exc: WebLoginRequired):
    response = RedirectResponse(LOGIN_PATH, status_code=303)
    response.headers["Cache-Control"] = "no-store"
    # Only a cookie the browser sent and Firebase refused is deleted. A
    # link from another site arrives without the SameSite=Strict cookie:
    # deleting it there would sign the admin out of the other tabs.
    if SESSION_COOKIE in request.cookies:
        delete_session_cookie(response)
    return response


def access_denied_handler(request: Request, exc: WebAccessDenied):
    response = render(
        request,
        "admin/error.html",
        {
            "title": "Accès refusé",
            "message": "Ce compte n'est pas un administrateur actif.",
        },
        status_code=403,
    )
    delete_session_cookie(response)
    return response


def csrf_rejected_handler(request: Request, exc: WebCsrfRejected):
    return render(
        request,
        "admin/error.html",
        {
            "title": "Formulaire expiré",
            "message": "Rechargez la page puis réessayez.",
        },
        status_code=403,
    )


def service_unavailable_handler(
    request: Request,
    exc: WebServiceUnavailable,
):
    return render(
        request,
        "admin/error.html",
        {
            "title": "Service indisponible",
            "message": "La connexion est momentanément impossible. "
            "Réessayez dans quelques minutes.",
        },
        status_code=503,
    )


def register_web_error_handlers(app: FastAPI) -> None:
    app.add_exception_handler(WebLoginRequired, login_required_handler)
    app.add_exception_handler(WebAccessDenied, access_denied_handler)
    app.add_exception_handler(WebCsrfRejected, csrf_rejected_handler)
    app.add_exception_handler(
        WebServiceUnavailable,
        service_unavailable_handler,
    )
