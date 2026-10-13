from dataclasses import dataclass

from fastapi import Depends, Request
from fastapi.responses import RedirectResponse
from starlette.responses import Response

from app.application.services.admin_web_session import AdminWebSession
from app.dependencies.admin_web_session import get_admin_web_session
from app.domain.errors import (
    AdminRequiredError,
    EmailNotVerifiedError,
    InactiveUserError,
    InvalidSessionError,
    SignInUnavailableError,
    UserNotFoundError,
)
from app.domain.user import User
from app.web.csrf import (
    check_token,
    delete_csrf_cookie,
    session_csrf_token,
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


# A valid account that may not use the back office. One message for all
# of them, so the page does not reveal why a given account is refused.
ACCESS_DENIED_ERRORS = (
    AdminRequiredError,
    EmailNotVerifiedError,
    InactiveUserError,
    UserNotFoundError,
)


@dataclass(frozen=True)
class AdminContext:
    """What an admin page knows about its visitor. Built by the server
    from the session cookie, never from a form or a header."""

    subject: User
    csrf_token: str


class AdminSecurity:
    """Contract expected by the Jinja pages of NW-127."""

    def __init__(self, session: AdminWebSession):
        self.session = session

    def require_active_admin(self, request: Request) -> AdminContext:
        """Valid session cookie and active admin profile, read again on
        each request."""
        session_cookie = request.cookies.get(SESSION_COOKIE)

        if not session_cookie:
            raise WebLoginRequired()

        try:
            admin = self.session.authenticate(session_cookie)
        except InvalidSessionError:
            raise WebLoginRequired() from None
        except ACCESS_DENIED_ERRORS:
            raise WebAccessDenied() from None
        except (SignInUnavailableError, *DEPENDENCY_ERRORS):
            raise WebServiceUnavailable() from None

        return AdminContext(
            subject=admin,
            csrf_token=session_csrf_token(session_cookie),
        )

    def verify_csrf(
        self,
        request: Request,
        context: AdminContext,
        token: str,
    ) -> None:
        """Call on every POST, with the csrf_token field of the form."""
        check_token(context.csrf_token, token)

    def logout(self, request: Request, context: AdminContext) -> Response:
        """Ends the browser session. Call verify_csrf first.

        The Firebase refresh tokens stay valid, so the admin's mobile app
        is not signed out."""
        response = RedirectResponse(LOGIN_PATH, status_code=303)
        response.headers["Cache-Control"] = "no-store"
        delete_session_cookie(response)
        delete_csrf_cookie(response)
        return response


def get_admin_security(
    session: AdminWebSession = Depends(get_admin_web_session),
) -> AdminSecurity:
    return AdminSecurity(session)


def get_admin_context(
    request: Request,
    security: AdminSecurity = Depends(get_admin_security),
) -> AdminContext:
    """Dependency of every admin page."""
    return security.require_active_admin(request)
