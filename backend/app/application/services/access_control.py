from app.application.ports.user_repository import UserRepository
from app.domain.errors import (
    AdminRequiredError,
    EmailNotVerifiedError,
    InactiveUserError,
    UserNotFoundError,
)
from app.domain.user import User, UserRole, UserStatus


def resolve_active_user(
    identity: dict,
    user_repository: UserRepository,
) -> User:
    """Shared by the mobile API and the admin web pages: a verified
    Firebase identity must match an active NoWave profile."""
    if not identity.get("email_verified", False):
        raise EmailNotVerifiedError(
            "email must be verified"
        )

    user = user_repository.get_by_firebase_uid(
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

    return user


def resolve_active_admin(
    identity: dict,
    user_repository: UserRepository,
) -> User:
    user = resolve_active_user(
        identity,
        user_repository,
    )

    if user.role != UserRole.ADMIN:
        raise AdminRequiredError(
            "an active administrator is required"
        )

    return user
