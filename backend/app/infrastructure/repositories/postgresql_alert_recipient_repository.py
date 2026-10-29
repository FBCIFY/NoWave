from uuid import UUID

from psycopg import Cursor

from app.domain.alert import ALERT_RADIUS_M, AlertRecipient


def select_alert_recipients(cursor: Cursor, report_id: UUID) -> list[AlertRecipient]:
    """Read recipients inside the publication transaction."""
    cursor.execute(
        """
        SELECT u.id,
               MIN(ST_Distance(p.position, r.final_position)),
               ARRAY_AGG(DISTINCT d.id ORDER BY d.id)
        FROM nowave.reports r
        JOIN nowave.users u ON u.id IS DISTINCT FROM r.author_id
        JOIN nowave.devices d ON d.user_id = u.id
        JOIN nowave.device_positions p ON p.device_id = d.id
        WHERE r.id = %s
          AND r.status = 'active'
          AND r.expires_at > statement_timestamp()
          AND u.status = 'active'
          AND u.notifications_enabled
          AND d.is_active
          AND d.fcm_token ~ '[^[:space:]]'
          AND p.accuracy_m BETWEEN 0 AND 50
          AND NOT ST_IsEmpty(p.position::geometry)
          AND ST_X(p.position::geometry) BETWEEN -180 AND 180
          AND ST_Y(p.position::geometry) BETWEEN -90 AND 90
          AND ST_DWithin(p.position, r.final_position, %s)
        GROUP BY u.id
        ORDER BY u.id
        """,
        (report_id, ALERT_RADIUS_M),
    )
    return [
        AlertRecipient(user_id, distance_m, tuple(device_ids))
        for user_id, distance_m, device_ids in cursor.fetchall()
    ]
