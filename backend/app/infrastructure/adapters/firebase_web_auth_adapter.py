from datetime import timedelta

import firebase_admin
import httpx
from firebase_admin import auth
from firebase_admin.exceptions import FirebaseError

from app.application.ports.web_auth_provider import WebAuthProvider
from app.config.settings import ConfigurationError
from app.domain.errors import (
    InvalidCredentialsError,
    InvalidSessionError,
    SignInUnavailableError,
)


SIGN_IN_URL = (
    "https://identitytoolkit.googleapis.com/v1/"
    "accounts:signInWithPassword"
)

# Firebase REST error codes caused by the submitted email or password.
# Any other code (quota, invalid API key, outage) means the service is
# unavailable, not that the admin typed something wrong.
CREDENTIAL_ERRORS = {
    "EMAIL_NOT_FOUND",
    "INVALID_EMAIL",
    "INVALID_LOGIN_CREDENTIALS",
    "INVALID_PASSWORD",
    "MISSING_EMAIL",
    "MISSING_PASSWORD",
    "USER_DISABLED",
}

# The ID token is checked a few milliseconds after Firebase issued it: a
# VPS clock slightly behind Google's must not reject it as "used too early".
CLOCK_SKEW_SECONDS = 10


class FirebaseWebAuthAdapter(WebAuthProvider):
    def __init__(
        self,
        api_key: str | None,
        http_client: httpx.Client | None = None,
    ):
        self.api_key = api_key
        self.http_client = http_client

    def sign_in_with_password(
        self,
        email: str,
        password: str,
    ) -> str:
        # Only the sign-in needs the Web API key: without it, existing
        # sessions keep working and the login page answers 503.
        if not self.api_key or not self.api_key.strip():
            raise ConfigurationError(
                "FIREBASE_WEB_API_KEY must be set for the admin sign-in"
            )

        try:
            response = self._post(
                SIGN_IN_URL,
                params={"key": self.api_key.strip()},
                json={
                    "email": email,
                    "password": password,
                    "returnSecureToken": True,
                },
                timeout=5,
            )
        except httpx.HTTPError:
            # The message of the exception holds the URL and its API key.
            raise SignInUnavailableError(
                "sign-in service unavailable"
            ) from None

        if response.status_code == 200:
            try:
                return response.json()["idToken"]
            except (ValueError, KeyError, TypeError):
                raise SignInUnavailableError(
                    "sign-in service unavailable"
                ) from None

        if firebase_error_code(response) in CREDENTIAL_ERRORS:
            raise InvalidCredentialsError(
                "invalid email or password"
            )

        raise SignInUnavailableError(
            "sign-in service unavailable"
        )

    def verify_id_token(self, id_token: str) -> dict:
        initialize_firebase()

        try:
            return auth.verify_id_token(
                id_token,
                clock_skew_seconds=CLOCK_SKEW_SECONDS,
            )
        except (ValueError, FirebaseError):
            # The token comes straight from Firebase: a rejection means a
            # setup problem (Web API key of another project, clock), not a
            # wrong password.
            raise SignInUnavailableError(
                "sign-in service unavailable"
            ) from None

    def create_session_cookie(
        self,
        id_token: str,
        expires_in: timedelta,
    ) -> str:
        initialize_firebase()

        try:
            return auth.create_session_cookie(
                id_token,
                expires_in=expires_in,
            )
        except (ValueError, FirebaseError):
            raise SignInUnavailableError(
                "session could not be created"
            ) from None

    def verify_session_cookie(self, session_cookie: str) -> dict:
        initialize_firebase()

        try:
            # check_revoked also rejects a disabled or deleted account.
            return auth.verify_session_cookie(
                session_cookie,
                check_revoked=True,
                clock_skew_seconds=CLOCK_SKEW_SECONDS,
            )
        except (
            ValueError,
            auth.InvalidSessionCookieError,
            auth.UserDisabledError,
            auth.UserNotFoundError,
        ):
            raise InvalidSessionError(
                "invalid admin session"
            ) from None
        except FirebaseError:
            raise SignInUnavailableError(
                "sign-in service unavailable"
            ) from None

    def _post(self, url: str, **kwargs) -> httpx.Response:
        if self.http_client is not None:
            return self.http_client.post(url, **kwargs)

        return httpx.post(url, **kwargs)


def firebase_error_code(response: httpx.Response) -> str | None:
    try:
        message = response.json()["error"]["message"]
    except (ValueError, KeyError, TypeError):
        return None

    if not isinstance(message, str):
        return None

    # For example "TOO_MANY_ATTEMPTS_TRY_LATER : Access to this account
    # has been temporarily disabled".
    return message.split(" ", 1)[0]


def initialize_firebase() -> None:
    try:
        firebase_admin.get_app()
    except ValueError:
        firebase_admin.initialize_app()
