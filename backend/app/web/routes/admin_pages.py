from fastapi import APIRouter, Depends, Form, Request
from fastapi.responses import RedirectResponse

from app.application.services.admin_web_session import (
    SESSION_DURATION,
    AdminWebSession,
)
from app.dependencies.admin_web_session import get_admin_web_session
from app.domain.errors import (
    InvalidCredentialsError,
    SignInUnavailableError,
)
from app.web.csrf import (
    check_login_csrf,
    delete_csrf_cookie,
    login_csrf_token,
    set_csrf_cookie,
)
from app.web.errors import (
    DEPENDENCY_ERRORS,
    SESSION_COOKIE,
)
from app.web.security import (
    ACCESS_DENIED_ERRORS,
    AdminContext,
    AdminSecurity,
    get_admin_context,
    get_admin_security,
)
from app.web.templating import render


# Pages for browsers, outside /api/v1 and its JSON errors.
router = APIRouter(
    prefix="/admin",
    include_in_schema=False,
)


def render_admin_page(
    request: Request,
    context: AdminContext,
    name: str,
    page_context: dict | None = None,
):
    """Render a signed-in page: its forms carry the session CSRF token."""
    return render(
        request,
        name,
        {
            **(page_context or {}),
            "admin": context.subject,
            "csrf_token": context.csrf_token,
        },
    )


def login_page(
    request: Request,
    error: str | None = None,
    email: str = "",
    status_code: int = 200,
):
    token = login_csrf_token(request)
    response = render(
        request,
        "admin/login.html",
        {"error": error, "email": email, "csrf_token": token},
        status_code=status_code,
    )
    set_csrf_cookie(response, token)
    return response


@router.get("/login")
def show_login(request: Request):
    return login_page(request)


@router.post("/login")
def submit_login(
    request: Request,
    email: str = Form(""),
    password: str = Form(""),
    csrf_token: str = Form(""),
    session: AdminWebSession = Depends(get_admin_web_session),
):
    # Before any call to Firebase: a forged form costs nothing.
    check_login_csrf(request, csrf_token)

    email = email.strip()

    if not email or not password:
        return login_page(
            request,
            error="Saisissez votre e-mail et votre mot de passe.",
            email=email,
            status_code=400,
        )

    try:
        session_cookie = session.sign_in(email, password)
    except InvalidCredentialsError:
        return login_page(
            request,
            error="E-mail ou mot de passe incorrect.",
            email=email,
            status_code=401,
        )
    except ACCESS_DENIED_ERRORS:
        return login_page(
            request,
            error="Ce compte n'a pas accès à l'administration.",
            email=email,
            status_code=403,
        )
    except (SignInUnavailableError, *DEPENDENCY_ERRORS):
        return login_page(
            request,
            error="Connexion momentanément impossible. "
            "Réessayez dans quelques minutes.",
            email=email,
            status_code=503,
        )

    response = RedirectResponse("/admin", status_code=303)
    response.headers["Cache-Control"] = "no-store"
    response.set_cookie(
        SESSION_COOKIE,
        session_cookie,
        max_age=int(SESSION_DURATION.total_seconds()),
        httponly=True,
        secure=True,
        samesite="strict",
        path="/",
    )
    # Signed-in forms use the session token: the login one is dropped.
    delete_csrf_cookie(response)
    return response


@router.post("/logout")
def logout(
    request: Request,
    csrf_token: str = Form(""),
    context: AdminContext = Depends(get_admin_context),
    security: AdminSecurity = Depends(get_admin_security),
):
    security.verify_csrf(request, context, csrf_token)
    return security.logout(request, context)


@router.get("/")
def redirect_home():
    # Otherwise Starlette's slash redirect would build an http:// URL, as
    # uvicorn ignores the proxy headers.
    return RedirectResponse("/admin", status_code=308)


@router.get("")
def show_home(
    request: Request,
    context: AdminContext = Depends(get_admin_context),
):
    # Placeholder until the moderation pages of NW-127.
    return render_admin_page(request, context, "admin/home.html")
