from contextlib import contextmanager
from datetime import datetime

from psycopg.rows import dict_row

from app.domain.notification import NotificationDelivery
from app.infrastructure.database.connection import database_connection


class NotificationAttempt:
    def __init__(self, cursor, delivery):
        self.cursor = cursor
        self.delivery = delivery

    def sent(self, now: datetime):
        self.cursor.execute(
            """UPDATE nowave.notifications
               SET status = 'sent', sent_at = %s, updated_at = %s,
                   attempt_count = attempt_count + 1, next_attempt_at = NULL, last_error_code = NULL
               WHERE id = %s""",
            (now, now, self.delivery.notification_id),
        )

    def failed(self, code, now, *, attempted=False):
        self.cursor.execute(
            """UPDATE nowave.notifications
               SET status = 'failed', updated_at = %s, next_attempt_at = NULL,
                   last_error_code = %s, attempt_count = attempt_count + %s
               WHERE id = %s""",
            (now, code, int(attempted), self.delivery.notification_id),
        )

    def retry(self, code, scheduled, now):
        self.cursor.execute(
            """UPDATE nowave.notifications
               SET next_attempt_at = %s, updated_at = %s, last_error_code = %s,
                   attempt_count = attempt_count + 1 WHERE id = %s""",
            (scheduled, now, code, self.delivery.notification_id),
        )

    def invalidate_token(self):
        self.cursor.execute(
            "UPDATE nowave.devices SET fcm_token = NULL WHERE id = %s AND fcm_token = %s",
            (self.delivery.device_id, self.delivery.fcm_token),
        )


class PostgreSQLNotificationRepository:
    def due_ids(self, limit=50):
        with database_connection() as connection:
            return [
                row[0]
                for row in connection.execute(
                    """SELECT n.id FROM nowave.notifications n
                   JOIN nowave.reports r ON r.id = n.report_id
                   WHERE n.status = 'pending'
                     AND (n.next_attempt_at <= statement_timestamp() OR r.expires_at <= statement_timestamp())
                   ORDER BY n.next_attempt_at, n.id LIMIT %s""",
                    (limit,),
                )
            ]

    @contextmanager
    def attempt(self, notification_id):
        with database_connection() as connection:
            with connection.cursor(row_factory=dict_row) as cursor:
                cursor.execute(
                    """SELECT n.report_id, n.device_id, d.user_id
                       FROM nowave.notifications n JOIN nowave.devices d ON d.id = n.device_id
                       WHERE n.id = %s AND n.status = 'pending'""",
                    (notification_id,),
                )
                candidate = cursor.fetchone()
                if candidate is None:
                    yield None
                    return

                # Parent locks first: device deletion locks the device before its notifications.
                cursor.execute(
                    "SELECT * FROM nowave.users WHERE id = %s FOR SHARE SKIP LOCKED",
                    (candidate["user_id"],),
                )
                user = cursor.fetchone()
                if user is None:
                    yield None
                    return
                cursor.execute(
                    "SELECT * FROM nowave.reports WHERE id = %s FOR SHARE SKIP LOCKED",
                    (candidate["report_id"],),
                )
                report = cursor.fetchone()
                if report is None:
                    yield None
                    return
                cursor.execute(
                    "SELECT * FROM nowave.devices WHERE id = %s FOR UPDATE SKIP LOCKED",
                    (candidate["device_id"],),
                )
                device = cursor.fetchone()
                if device is None:
                    yield None
                    return
                cursor.execute(
                    "SELECT *, clock_timestamp() AS checked_at FROM nowave.notifications "
                    "WHERE id = %s FOR UPDATE SKIP LOCKED",
                    (notification_id,),
                )
                notification = cursor.fetchone()
                if notification is None or notification["status"] != "pending":
                    yield None
                    return
                if (
                    notification["device_id"] != device["id"]
                    or notification["report_id"] != report["id"]
                ):
                    yield None
                    return
                now = notification["checked_at"]
                if notification["next_attempt_at"] > now and report["expires_at"] > now:
                    yield None
                    return

                cursor.execute(
                    """SELECT id AS alert_id, category, distance_m, alerted_at,
                              ST_X(position::geometry) AS longitude, ST_Y(position::geometry) AS latitude
                       FROM nowave.alert_history
                       WHERE user_id = %s AND report_id = %s AND report_version = %s""",
                    (user["id"], report["id"], notification["report_version"]),
                )
                history = cursor.fetchone()
                reason = self._ineligible_reason(
                    user, report, device, notification, history, now
                )
                if reason:
                    cursor.execute(
                        """UPDATE nowave.notifications SET status = 'failed', next_attempt_at = NULL,
                           last_error_code = %s, updated_at = %s WHERE id = %s""",
                        (reason, now, notification_id),
                    )
                    yield None
                    return

                delivery = NotificationDelivery(
                    notification_id=notification_id,
                    device_id=device["id"],
                    report_id=report["id"],
                    report_version=notification["report_version"],
                    expires_at=report["expires_at"],
                    attempt_count=notification["attempt_count"],
                    fcm_token=device["fcm_token"],
                    **history,
                )
                yield NotificationAttempt(cursor, delivery)

    @staticmethod
    def _ineligible_reason(user, report, device, notification, history, now):
        if notification["report_version"] != report["version"]:
            return "report_version_changed"
        if report["status"] != "active":
            return "report_not_visible"
        if report["expires_at"] <= now:
            return "report_expired"
        if user["status"] != "active":
            return "user_inactive"
        if not user["notifications_enabled"]:
            return "consent_revoked"
        if device["user_id"] != user["id"] or user["id"] == report["author_id"]:
            return "device_owner_changed"
        if not device["is_active"]:
            return "device_inactive"
        if not device["fcm_token"] or not device["fcm_token"].strip():
            return "device_token_missing"
        if history is None:
            return "alert_history_missing"
        return None

    def expire_pending(self, limit=500):
        with database_connection() as connection:
            result = connection.execute(
                """UPDATE nowave.notifications
                   SET status = 'failed', next_attempt_at = NULL,
                       last_error_code = 'report_expired', updated_at = statement_timestamp()
                   WHERE id IN (
                       SELECT n.id FROM nowave.notifications n
                       JOIN nowave.reports r ON r.id = n.report_id
                       WHERE n.status = 'pending' AND r.expires_at <= statement_timestamp()
                       ORDER BY n.next_attempt_at, n.id LIMIT %s FOR UPDATE OF n SKIP LOCKED
                   )""",
                (limit,),
            )
            return result.rowcount

    def purge(self, limit=500):
        with database_connection() as connection:
            result = connection.execute(
                """DELETE FROM nowave.notifications WHERE id IN (
                       SELECT id FROM nowave.notifications
                       WHERE status IN ('sent', 'failed')
                         AND updated_at < statement_timestamp() - interval '7 days'
                       ORDER BY updated_at, id LIMIT %s FOR UPDATE SKIP LOCKED
                   )""",
                (limit,),
            )
            return result.rowcount
