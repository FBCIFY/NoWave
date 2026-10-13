from datetime import timedelta

from app.application.ports.user_repository import UserRepository
from app.application.ports.web_auth_provider import WebAuthProvider
from app.application.services.access_control import resolve_active_admin
from app.domain.user import User


# Firebase accepts session cookies from 5 minutes to 14 days. A working
# day keeps a stolen cookie short-lived without logging admins out mid-task.
SESSION_DURATION = timedelta(hours=8)


class AdminWebSession:
    """Sign-in and session checks for the admin web pages. The active
    admin rule is the one used by the /api/v1/admin routes."""

    def __init__(
        self,
        web_auth_provider: WebAuthProvider,
        user_repository: UserRepository,
    ):
        self.web_auth_provider = web_auth_provider
        self.user_repository = user_repository

    def sign_in(self, email: str, password: str) -> str:
        id_token = self.web_auth_provider.sign_in_with_password(
            email,
            password,
        )
        identity = self.web_auth_provider.verify_id_token(id_token)

        # Checked before the cookie exists: a non-admin never gets a session.
        resolve_active_admin(identity, self.user_repository)

        return self.web_auth_provider.create_session_cookie(
            id_token,
            SESSION_DURATION,
        )

    def authenticate(self, session_cookie: str) -> User:
        identity = self.web_auth_provider.verify_session_cookie(
            session_cookie
        )

        # Read on every page: a suspension or a role change applies at
        # the next request, not when the cookie expires.
        return resolve_active_admin(identity, self.user_repository)
