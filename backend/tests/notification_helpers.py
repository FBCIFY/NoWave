from datetime import UTC, datetime, timedelta
from uuid import uuid4

from app.domain.notification import NotificationDelivery


def delivery(**changes):
    now = datetime.now(UTC)
    values = dict(
        notification_id=uuid4(),
        device_id=uuid4(),
        alert_id=uuid4(),
        report_id=uuid4(),
        report_version=1,
        category="pollution",
        longitude=5.4,
        latitude=43.31,
        distance_m=1000.0,
        alerted_at=now,
        expires_at=now + timedelta(hours=1),
        attempt_count=0,
        fcm_token="test-token",
    )
    values.update(changes)
    return NotificationDelivery(**values)


class RecordingPushSender:
    def __init__(self, error=None):
        self.deliveries = []
        self.error = error

    def prepare(self):
        pass

    def send(self, delivery, now):
        self.deliveries.append(delivery)
        if self.error:
            raise self.error
        return "projects/test/messages/accepted"
