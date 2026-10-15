from datetime import UTC, datetime
import logging

from app.domain.notification import PushSendError, next_attempt_at


logger = logging.getLogger(__name__)


class SendNotifications:
    def __init__(self, repository, sender, clock=None):
        self.repository = repository
        self.sender = sender
        self.clock = clock or (lambda: datetime.now(UTC))

    def run_once(self, stop=None):
        sent = 0
        for notification_id in self.repository.due_ids():
            if stop is not None and stop.is_set():
                break
            self.sender.prepare()
            if stop is not None and stop.is_set():
                break
            with self.repository.attempt(notification_id) as attempt:
                if attempt is None:
                    continue
                now = self.clock()
                if attempt.delivery.expires_at <= now:
                    attempt.failed("report_expired", now)
                    continue
                try:
                    self.sender.send(attempt.delivery, now)
                except PushSendError as error:
                    now = self.clock()
                    if error.invalid_token:
                        attempt.invalidate_token()
                    scheduled = next_attempt_at(
                        attempt.delivery.attempt_count, now, error.retry_after
                    )
                    if error.permanent:
                        attempt.failed(error.code, now, attempted=True)
                    elif scheduled >= attempt.delivery.expires_at:
                        attempt.failed("retry_after_expiry", now, attempted=True)
                    else:
                        attempt.retry(error.code, scheduled, now)
                    logger.warning("Notification %s: %s", notification_id, error.code)
                else:
                    attempt.sent(self.clock())
                    sent += 1
        return sent
