from dataclasses import dataclass
from uuid import UUID

from fastapi import APIRouter, Depends, Form, Query, Request
from fastapi.responses import RedirectResponse

from app.application.services.admin_reads import AdminReadService
from app.application.services.admin_web_session import (
    SESSION_DURATION,
    AdminWebSession,
)
from app.application.services.moderation import ModerationService
from app.dependencies.admin_web_session import get_admin_web_session
from app.domain.errors import (
    InvalidCredentialsError,
    ModerationConflictError,
    PhotoNotFoundError,
    ReportNotFoundError,
    SignInUnavailableError,
    UserNotFoundError,
)
from app.domain.pagination import (
    DEFAULT_PAGE_LIMIT,
    MAX_PAGE,
    MAX_PAGE_LIMIT,
)
from app.web.csrf import (
    check_login_csrf,
    delete_csrf_cookie,
    login_csrf_token,
    set_csrf_cookie,
)
from app.infrastructure.repositories.postgresql_admin_read_repository import (
    PostgreSQLAdminReadRepository,
)
from app.infrastructure.repositories.postgresql_moderation_repository import (
    PostgreSQLModerationRepository,
)
from app.infrastructure.repositories.postgresql_report_detail_repository import (
    PostgreSQLReportDetailRepository,
)
from app.web.errors import (
    DEPENDENCY_ERRORS,
    SESSION_COOKIE,
    WebServiceUnavailable,
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
    status_code: int = 200,
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
        status_code=status_code,
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


# NW-127 moderation pages


@dataclass(frozen=True)
class AdminAction:
    collection: str
    label: str
    service_method: str


ADMIN_ACTIONS = {
    ("reports", "remove"): AdminAction(
        collection="reports",
        label="Retirer le signalement",
        service_method="remove_report",
    ),
    ("reports", "restore"): AdminAction(
        collection="reports",
        label="Restaurer le signalement",
        service_method="restore_report",
    ),
    ("reports", "hide-photo"): AdminAction(
        collection="reports",
        label="Masquer la photo",
        service_method="hide_photo",
    ),
    ("users", "suspend"): AdminAction(
        collection="users",
        label="Suspendre l’utilisateur",
        service_method="suspend_user",
    ),
    ("users", "reactivate"): AdminAction(
        collection="users",
        label="Réactiver l’utilisateur",
        service_method="reactivate_user",
    ),
}


def get_admin_read_service() -> AdminReadService:
    return AdminReadService(
        admin_read_repository=PostgreSQLAdminReadRepository(),
    )


def get_moderation_service() -> ModerationService:
    return ModerationService(
        moderation_repository=PostgreSQLModerationRepository(),
        report_detail_repository=PostgreSQLReportDetailRepository(),
    )


def render_admin_error(
    request: Request,
    context: AdminContext,
    title: str,
    message: str,
    status_code: int,
):
    return render_admin_page(
        request,
        context,
        "admin/error.html",
        {
            "title": title,
            "message": message,
        },
        status_code=status_code,
    )


def render_action_page(
    request: Request,
    context: AdminContext,
    action: AdminAction,
    target_id: UUID,
    reason: str = "",
    error: str | None = None,
    uncertain: bool = False,
    status_code: int = 200,
):
    return render_admin_page(
        request,
        context,
        "admin/action.html",
        {
            "action": action,
            "target_id": target_id,
            "reason": reason,
            "error": error,
            "uncertain": uncertain,
        },
        status_code=status_code,
    )


@router.get("/reports", name="admin_reports")
def admin_reports(
    request: Request,
    page: int = Query(default=1, ge=1, le=MAX_PAGE),
    limit: int = Query(
        default=DEFAULT_PAGE_LIMIT,
        ge=1,
        le=MAX_PAGE_LIMIT,
    ),
    context: AdminContext = Depends(get_admin_context),
    service: AdminReadService = Depends(get_admin_read_service),
):
    try:
        result = service.list_reports(page=page, limit=limit)
    except DEPENDENCY_ERRORS:
        raise WebServiceUnavailable() from None

    return render_admin_page(
        request,
        context,
        "admin/reports.html",
        {
            "result": result,
            "page": page,
            "limit": limit,
        },
    )


@router.get("/reports/{target_id}", name="admin_report")
def admin_report(
    target_id: UUID,
    request: Request,
    context: AdminContext = Depends(get_admin_context),
    service: AdminReadService = Depends(get_admin_read_service),
):
    try:
        item = service.get_report(report_id=target_id)
    except ReportNotFoundError:
        return render_admin_error(
            request,
            context,
            "Signalement introuvable",
            "Ce signalement n’existe pas ou n’est plus disponible.",
            404,
        )
    except DEPENDENCY_ERRORS:
        raise WebServiceUnavailable() from None

    return render_admin_page(
        request,
        context,
        "admin/report.html",
        {"item": item},
    )


@router.get("/users", name="admin_users")
def admin_users(
    request: Request,
    page: int = Query(default=1, ge=1, le=MAX_PAGE),
    limit: int = Query(
        default=DEFAULT_PAGE_LIMIT,
        ge=1,
        le=MAX_PAGE_LIMIT,
    ),
    context: AdminContext = Depends(get_admin_context),
    service: AdminReadService = Depends(get_admin_read_service),
):
    try:
        result = service.list_users(page=page, limit=limit)
    except DEPENDENCY_ERRORS:
        raise WebServiceUnavailable() from None

    return render_admin_page(
        request,
        context,
        "admin/users.html",
        {
            "result": result,
            "page": page,
            "limit": limit,
        },
    )


@router.get("/audit", name="admin_audit")
def admin_audit(
    request: Request,
    page: int = Query(default=1, ge=1, le=MAX_PAGE),
    limit: int = Query(
        default=DEFAULT_PAGE_LIMIT,
        ge=1,
        le=MAX_PAGE_LIMIT,
    ),
    context: AdminContext = Depends(get_admin_context),
    service: AdminReadService = Depends(get_admin_read_service),
):
    try:
        result = service.list_moderation_actions(
            page=page,
            limit=limit,
        )
    except DEPENDENCY_ERRORS:
        raise WebServiceUnavailable() from None

    return render_admin_page(
        request,
        context,
        "admin/moderation-actions.html",
        {
            "result": result,
            "page": page,
            "limit": limit,
        },
    )


@router.get(
    "/actions/{collection}/{target_id}/{action_name}",
    name="admin_action",
)
def admin_action(
    collection: str,
    target_id: UUID,
    action_name: str,
    request: Request,
    context: AdminContext = Depends(get_admin_context),
):
    action = ADMIN_ACTIONS.get((collection, action_name))

    if action is None:
        return render_admin_error(
            request,
            context,
            "Action inconnue",
            "Cette action de modération n’existe pas.",
            404,
        )

    return render_action_page(
        request,
        context,
        action,
        target_id,
    )


@router.post(
    "/actions/{collection}/{target_id}/{action_name}",
)
def submit_admin_action(
    collection: str,
    target_id: UUID,
    action_name: str,
    request: Request,
    reason: str = Form(""),
    confirmed: str = Form(""),
    csrf_token: str = Form(""),
    context: AdminContext = Depends(get_admin_context),
    security: AdminSecurity = Depends(get_admin_security),
    service: ModerationService = Depends(get_moderation_service),
):
    security.verify_csrf(request, context, csrf_token)

    action = ADMIN_ACTIONS.get((collection, action_name))

    if action is None:
        return render_admin_error(
            request,
            context,
            "Action inconnue",
            "Cette action de modération n’existe pas.",
            404,
        )

    reason = reason.strip()

    if not reason:
        return render_action_page(
            request,
            context,
            action,
            target_id,
            reason=reason,
            error="Le motif est obligatoire.",
            status_code=422,
        )

    if confirmed != "yes":
        return render_action_page(
            request,
            context,
            action,
            target_id,
            reason=reason,
            error="Vous devez confirmer explicitement cette action.",
            status_code=400,
        )

    try:
        if action.service_method == "remove_report":
            service.remove_report(
                admin=context.subject,
                report_id=target_id,
                reason=reason,
            )
        elif action.service_method == "restore_report":
            service.restore_report(
                admin=context.subject,
                report_id=target_id,
                reason=reason,
            )
        elif action.service_method == "hide_photo":
            service.hide_photo(
                admin=context.subject,
                report_id=target_id,
                reason=reason,
            )
        elif action.service_method == "suspend_user":
            service.suspend_user(
                admin=context.subject,
                user_id=target_id,
                reason=reason,
            )
        elif action.service_method == "reactivate_user":
            service.reactivate_user(
                admin=context.subject,
                user_id=target_id,
                reason=reason,
            )
    except ModerationConflictError:
        return render_action_page(
            request,
            context,
            action,
            target_id,
            reason=reason,
            error="Cette action n’est pas possible dans l’état actuel.",
            status_code=409,
        )
    except PhotoNotFoundError:
        return render_action_page(
            request,
            context,
            action,
            target_id,
            reason=reason,
            error="Ce signalement ne possède aucune photo à masquer.",
            status_code=404,
        )
    except (ReportNotFoundError, UserNotFoundError):
        return render_action_page(
            request,
            context,
            action,
            target_id,
            reason=reason,
            error="La cible de cette action est introuvable.",
            status_code=404,
        )
    except ValueError:
        return render_action_page(
            request,
            context,
            action,
            target_id,
            reason=reason,
            error="Le motif fourni n’est pas valide.",
            status_code=422,
        )
    except DEPENDENCY_ERRORS:
        return render_action_page(
            request,
            context,
            action,
            target_id,
            reason=reason,
            error="Le service est momentanément indisponible.",
            uncertain=True,
            status_code=503,
        )

    return render_admin_page(
        request,
        context,
        "admin/success.html",
        {
            "action": action,
            "target_id": target_id,
        },
    )
