"""Send one real report push to one explicitly selected installation.

Run inside the backend environment. Without --send this is read-only and does
not initialize Firebase. Test sends deliberately bypass the proximity radius;
the normal notification worker and its author exclusion are unchanged.
"""

import argparse
from dataclasses import replace
from datetime import UTC, datetime, timedelta
import json
from uuid import UUID, uuid4

import psycopg
from psycopg.rows import dict_row

from app.domain.notification import NotificationDelivery, PushSendError
from app.infrastructure.adapters.firebase_push_sender import FirebasePushSender
from app.infrastructure.database.connection import (
    close_database_pools,
    database_connection,
)


def validate_target(row, now, *, allow_own_report=False):
    if row is None:
        raise ValueError("Account, installation, report or device position not found")
    if row["user_status"] != "active" or not row["notifications_enabled"]:
        raise ValueError("The account must be active with alerts enabled")
    if not row["is_active"] or not row["fcm_token"]:
        raise ValueError("The installation must be active and registered for push")
    if row["report_status"] != "active" or row["expires_at"] <= now:
        raise ValueError("The report is no longer available")
    if abs(now - row["measured_at"]) > timedelta(minutes=5):
        raise ValueError("Open the app to refresh the installation's GPS position")
    if row["author_id"] == row["user_id"] and not allow_own_report:
        raise ValueError("Testing your own report requires --allow-own-report")


def load_target(cursor, user_id, installation_id, report_id):
    cursor.execute(
        """SELECT u.id AS user_id, u.firebase_uid, u.status AS user_status,
                  u.notifications_enabled, d.id AS device_id, d.platform,
                  d.is_active, d.fcm_token, p.measured_at,
                  r.id AS report_id, r.author_id, r.version AS report_version,
                  r.status AS report_status, r.expires_at, r.category,
                  r.description, ST_X(r.final_position::geometry) AS longitude,
                  ST_Y(r.final_position::geometry) AS latitude,
                  ST_Distance(p.position, r.final_position) AS distance_m
           FROM nowave.users u
           JOIN nowave.devices d ON d.user_id = u.id
           JOIN nowave.device_positions p ON p.device_id = d.id
           CROSS JOIN nowave.reports r
           WHERE u.id = %s AND d.installation_id = %s AND r.id = %s""",
        (user_id, installation_id, report_id),
    )
    return cursor.fetchone()


def delivery_for(row, now):
    return NotificationDelivery(
        notification_id=uuid4(), device_id=row["device_id"], alert_id=uuid4(),
        report_id=row["report_id"], report_version=row["report_version"],
        category=row["category"], longitude=row["longitude"],
        latitude=row["latitude"], distance_m=row["distance_m"],
        alerted_at=now, expires_at=row["expires_at"], attempt_count=0,
        fcm_token=row["fcm_token"], description=row["description"],
        recipient_firebase_uid=row["firebase_uid"],
    )


def ensure_history(cursor, row, delivery):
    cursor.execute(
        """INSERT INTO nowave.alert_history
               (id, user_id, report_id, report_version, category, position,
                distance_m, alerted_at)
           SELECT %s, %s, id, version, category, final_position, %s, %s
           FROM nowave.reports WHERE id = %s
           ON CONFLICT ON CONSTRAINT alert_history_recipient_key DO NOTHING""",
        (delivery.alert_id, row["user_id"], delivery.distance_m,
         delivery.alerted_at, delivery.report_id),
    )
    cursor.execute(
        """SELECT id, alerted_at, distance_m FROM nowave.alert_history
           WHERE user_id = %s AND report_id = %s AND report_version = %s""",
        (row["user_id"], delivery.report_id, delivery.report_version),
    )
    history = cursor.fetchone()
    return replace(delivery, alert_id=history["id"],
                   alerted_at=history["alerted_at"], distance_m=history["distance_m"])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--user-id", required=True, type=UUID)
    parser.add_argument("--installation-id", required=True, type=UUID)
    parser.add_argument("--report-id", required=True, type=UUID)
    parser.add_argument("--allow-own-report", action="store_true")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--dry-run", action="store_true",
                      help="Validate only (the default); no database write or FCM send")
    mode.add_argument("--send", action="store_true",
                        help="Send one push; otherwise only validate the target")
    args = parser.parse_args()
    sender = None
    try:
        with database_connection() as connection:
            with connection.cursor(row_factory=dict_row) as cursor:
                cursor.execute("SET TRANSACTION READ ONLY")
                row = load_target(cursor, args.user_id, args.installation_id, args.report_id)
                now = datetime.now(UTC)
                validate_target(row, now, allow_own_report=args.allow_own_report)
                delivery = delivery_for(row, now)
        if args.send:
            sender = FirebasePushSender.from_environment()
            sender.prepare()
            with database_connection() as connection:
                with connection.cursor(row_factory=dict_row) as cursor:
                    # Revalidate after credential preparation, before persisting history.
                    row = load_target(cursor, args.user_id, args.installation_id, args.report_id)
                    now = datetime.now(UTC)
                    validate_target(row, now, allow_own_report=args.allow_own_report)
                    delivery = ensure_history(cursor, row, delivery_for(row, now))
            # History is committed before delivery. A failed FCM send can be
            # retried with the same arguments without duplicating the history.
            sender.send(delivery, datetime.now(UTC))
        print(json.dumps({
            "status": "fcm_accepted" if args.send else "dry_run",
            "user_id": str(args.user_id), "installation_id": str(args.installation_id),
            "report_id": str(args.report_id), "platform": row["platform"],
            "alert_id": str(delivery.alert_id) if args.send else None,
            "own_report": row["author_id"] == row["user_id"],
        }))
    except (ValueError, PushSendError) as error:
        parser.exit(1, f"Test push failed: {error}\n")
    except psycopg.Error:
        parser.exit(1, "Test push failed: database unavailable\n")
    finally:
        if sender is not None:
            sender.close()
        close_database_pools()


if __name__ == "__main__":
    main()
