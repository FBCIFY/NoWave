from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.domain.errors import (
    EmailNotVerifiedError,
    InactiveUserError,
    UserNotFoundError,
)
from app.domain.user import UserStatus
from app.infrastructure.adapters.firebase_auth_adapter import FirebaseAuthAdapter
from app.infrastructure.repositories.postgresql_user_repository import (
    PostgreSQLUserRepository,
)


bearer_scheme = HTTPBearer(auto_error=False)


def get_authenticated_identity(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
) -> dict:
    if credentials is None:
        raise HTTPException(
            status_code=401,
            detail="Authentication required",
        )

    adapter = FirebaseAuthAdapter()

    try:
        identity = adapter.verify_token(credentials.credentials)
    except Exception:
        raise HTTPException(
            status_code=401,
            detail="Invalid authentication token",
        )

    return identity


def get_current_identity(
    identity: dict = Depends(get_authenticated_identity),
) -> dict:
    if not identity.get("email_verified", False):
        raise EmailNotVerifiedError(
            "email must be verified"
        )

    repository = PostgreSQLUserRepository()

    user = repository.get_by_firebase_uid(
        identity["uid"]
    )

    if user is None:
        raise UserNotFoundError(
            "user profile not found"
        )

    if user.status != UserStatus.ACTIVE:
        raise InactiveUserError(
            "user is not active"
        )

    return identity
