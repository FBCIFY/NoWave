from abc import ABC, abstractmethod
from datetime import timedelta


class WebAuthProvider(ABC):
    """Browser sign-in for the admin pages. The password goes to the
    identity provider; the browser only keeps a session cookie."""

    @abstractmethod
    def sign_in_with_password(
        self,
        email: str,
        password: str,
    ) -> str:
        """Return a fresh ID token, or raise InvalidCredentialsError."""

    @abstractmethod
    def verify_id_token(self, id_token: str) -> dict:
        """Return the identity of a token just returned by the sign-in."""

    @abstractmethod
    def create_session_cookie(
        self,
        id_token: str,
        expires_in: timedelta,
    ) -> str:
        pass

    @abstractmethod
    def verify_session_cookie(self, session_cookie: str) -> dict:
        """Return the identity, or raise InvalidSessionError."""
