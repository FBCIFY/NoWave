from firebase_admin import auth as firebase_auth
from firebase_admin.exceptions import FirebaseError
from google.auth.exceptions import GoogleAuthError
from requests.exceptions import RequestException

from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.application.ports.user_repository import UserRepository
from app.application.repositories.preloaded_user_repository import PreloadedUserRepository
from app.application.services.access_control import (
    resolve_active_admin,
    resolve_active_user,
)
from app.domain.user import User
from app.infrastructure.adapters.firebase_auth_adapter import FirebaseAuthAdapter
from app.infrastructure.repositories.postgresql_user_repository import (
    PostgreSQLUserRepository,
)


bearer_scheme = HTTPBearer(auto_error=False)


class CurrentIdentity(dict):
    """Verified claims plus a server-loaded profile, outside the JSON claims."""

    def __init__(self, identity: dict, user: User):
        super().__init__(identity)
        self.user = user


def reuse_current_user(identity: dict, repository: UserRepository) -> UserRepository:
    if isinstance(identity, CurrentIdentity):
        return PreloadedUserRepository(repository, identity.user)
    return repository


def get_authenticated_identity(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
) -> dict:
    if credentials is None:
        raise HTTPException(
            status_code=401,
            detail="Authentication required",
        )

    try:
        adapter = FirebaseAuthAdapter()
    except (ValueError, OSError, FirebaseError, GoogleAuthError):
        raise HTTPException(
            status_code=503,
            detail="Authentication service unavailable",
        ) from None

    try:
        identity = adapter.verify_token(credentials.credentials)
    except (
        ValueError,
        firebase_auth.InvalidIdTokenError,
        firebase_auth.UserDisabledError,
        firebase_auth.UserNotFoundError,
    ):
        raise HTTPException(
            status_code=401,
            detail="Invalid authentication token",
        ) from None
    except (FirebaseError, GoogleAuthError, RequestException):
        raise HTTPException(
            status_code=503,
            detail="Authentication service unavailable",
        ) from None

    return identity


def get_current_identity(
    identity: dict = Depends(get_authenticated_identity),
) -> dict:
    user = resolve_active_user(
        identity,
        PostgreSQLUserRepository(),
    )

    return CurrentIdentity(identity, user)


def get_current_admin(
    identity: dict = Depends(get_authenticated_identity),
) -> User:
    # Same checks as get_current_identity, with a single profile read.
    return resolve_active_admin(
        identity,
        PostgreSQLUserRepository(),
    )
