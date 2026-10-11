import secrets

from fastapi import APIRouter, Depends, Form, Request
from fastapi.responses import RedirectResponse

from app.application.services.admin_web_session import (
    SESSION_DURATION,
    AdminWebSession,
)
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
from app.domain.user import User
from app.web.csrf import (
    check_csrf,
    csrf_token_for,
    delete_csrf_cookie,
    require_csrf,
    set_csrf_cookie,
)
from app.web.errors import (
    DEPENDENCY_ERRORS,
    LOGIN_PATH,
    SESSION_COOKIE,
    WebAccessDenied,
    WebLoginRequired,
    WebServiceUnavailable,
    delete_session_cookie,
)
from app.web.templating import render


# Pages for browsers, outside /api/v1 and its JSON errors.
router = APIRouter(
    prefix="/admin",
    include_in_schema=False,
)

# A valid account that may not use the back office. One message for all
# of them, so the page does not reveal why a given account is refused.
ACCESS_DENIED_ERRORS = (
    AdminRequiredError,
    EmailNotVerifiedError,
    InactiveUserError,
    UserNotFoundError,
)


def get_current_web_admin(
    request: Request,
    session: AdminWebSession = Depends(get_admin_web_session),
) -> User:
    """Every admin page depends on this: a valid session cookie and an
    active admin profile, read again on each request."""
    session_cookie = request.cookies.get(SESSION_COOKIE)

    if not session_cookie:
        raise WebLoginRequired()

    try:
        return session.authenticate(session_cookie)
    except InvalidSessionError:
        raise WebLoginRequired() from None
    except ACCESS_DENIED_ERRORS:
        raise WebAccessDenied() from None
    except (SignInUnavailableError, *DEPENDENCY_ERRORS):
        raise WebServiceUnavailable() from None


def render_page(
    request: Request,
    name: str,
    context: dict | None = None,
    status_code: int = 200,
):
    """Render a page with forms: every form carries the CSRF token."""
    token = csrf_token_for(request)
    response = render(
        request,
        name,
        {**(context or {}), "csrf_token": token},
        status_code=status_code,
    )
    set_csrf_cookie(response, token)
    return response


def login_page(
    request: Request,
    error: str | None = None,
    email: str = "",
    status_code: int = 200,
):
    return render_page(
        request,
        "admin/login.html",
        {"error": error, "email": email},
        status_code=status_code,
    )


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
    check_csrf(request, csrf_token)

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
    # New token once signed in: a token seen before login is useless.
    set_csrf_cookie(response, secrets.token_urlsafe(32))
    return response


@router.post("/logout", dependencies=[Depends(require_csrf)])
def logout():
    # Only the browser session ends: the Firebase refresh tokens stay
    # valid, so the admin's mobile app is not signed out.
    response = RedirectResponse(LOGIN_PATH, status_code=303)
    response.headers["Cache-Control"] = "no-store"
    delete_session_cookie(response)
    delete_csrf_cookie(response)
    return response


@router.get("/")
def redirect_home():
    # Otherwise Starlette's slash redirect would build an http:// URL, as
    # uvicorn ignores the proxy headers.
    return RedirectResponse("/admin", status_code=308)


@router.get("")
def show_home(
    request: Request,
    admin: User = Depends(get_current_web_admin),
):
    # Placeholder until the moderation pages of NW-127.
    return render_page(
        request,
        "admin/home.html",
        {"admin": admin},
    )
