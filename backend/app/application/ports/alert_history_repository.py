from abc import ABC, abstractmethod
from uuid import UUID

from app.domain.alert import Alert
from app.domain.pagination import Page


class AlertHistoryRepository(ABC):
    """Alerts received by one user, newest first."""

    @abstractmethod
    def list_for_user(
        self,
        user_id: UUID,
        page: int,
        limit: int,
    ) -> Page[Alert]:
        pass
