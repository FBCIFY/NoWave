from app.application.services.admin_web_session import AdminWebSession
from app.config.settings import get_settings
from app.infrastructure.adapters.firebase_web_auth_adapter import (
    FirebaseWebAuthAdapter,
)
from app.infrastructure.repositories.postgresql_user_repository import (
    PostgreSQLUserRepository,
)


def get_admin_web_session() -> AdminWebSession:
    return AdminWebSession(
        web_auth_provider=FirebaseWebAuthAdapter(
            api_key=get_settings().firebase_web_api_key,
        ),
        user_repository=PostgreSQLUserRepository(),
    )
