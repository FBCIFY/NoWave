import logging
import signal
from threading import Event
from time import monotonic

import psycopg

from app.application.services.send_notifications import SendNotifications
from app.config.settings import ConfigurationError
from app.domain.notification import PushSendError
from app.infrastructure.adapters.firebase_push_sender import FirebasePushSender
from app.infrastructure.database.connection import close_database_pools
from app.infrastructure.repositories.postgresql_notification_repository import (
    PostgreSQLNotificationRepository,
)


logger = logging.getLogger(__name__)


def main():
    logging.basicConfig(level=logging.INFO)
    stop = Event()
    for signum in (signal.SIGINT, signal.SIGTERM):
        signal.signal(signum, lambda *_: stop.set())
    repository = PostgreSQLNotificationRepository()
    sender = None
    next_purge = 0
    try:
        while not stop.is_set():
            delay = 1
            try:
                repository.expire_pending()
                if monotonic() >= next_purge:
                    purged = repository.purge()
                    next_purge = monotonic() + (1 if purged == 500 else 3600)
                if sender is None:
                    sender = FirebasePushSender.from_environment()
                sent = SendNotifications(repository, sender).run_once(stop=stop)
                if sent:
                    logger.info("FCM accepted %s notifications", sent)
            except (psycopg.Error, ConfigurationError):
                logger.warning("Notification database unavailable")
                delay = 60
            except PushSendError as error:
                logger.warning("Notification sender unavailable: %s", error.code)
                delay = 60
            stop.wait(delay)
    finally:
        if sender is not None:
            sender.close()
        close_database_pools()


if __name__ == "__main__":
    main()
