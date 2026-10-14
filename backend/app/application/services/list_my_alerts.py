from app.application.ports.alert_history_repository import (
    AlertHistoryRepository,
)
from app.application.ports.user_repository import UserRepository
from app.domain.alert import Alert
from app.domain.errors import UserNotFoundError
from app.domain.pagination import (
    DEFAULT_PAGE_LIMIT,
    Page,
    validate_page,
)


class ListMyAlerts:
    """History of the alerts the user received. Entries are kept even
    when the push failed, and have no read/unread state."""

    def __init__(
        self,
        user_repository: UserRepository,
        alert_history_repository: AlertHistoryRepository,
    ):
        self.user_repository = user_repository
        self.alert_history_repository = alert_history_repository

    def execute(
        self,
        firebase_uid: str,
        page: int = 1,
        limit: int = DEFAULT_PAGE_LIMIT,
    ) -> Page[Alert]:
        validate_page(page, limit)

        user = self.user_repository.get_by_firebase_uid(
            firebase_uid
        )

        if user is None:
            raise UserNotFoundError(
                "user profile not found"
            )

        return self.alert_history_repository.list_for_user(
            user_id=user.id,
            page=page,
            limit=limit,
        )
