from abc import ABC, abstractmethod
from datetime import datetime

from app.domain.notification import NotificationDelivery


class PushSender(ABC):
    @abstractmethod
    def prepare(self) -> None:
        """Refresh credentials before holding database locks."""

    @abstractmethod
    def send(self, delivery: NotificationDelivery, now: datetime) -> str:
        """Return the FCM acceptance ID, or raise PushSendError. Never retry here."""
