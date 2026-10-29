from datetime import UTC, datetime
from uuid import uuid4

from psycopg.rows import dict_row

from backend.tools.send_test_notification import (
    delivery_for,
    ensure_history,
    load_target,
    validate_target,
)


def prepare(conn, ids):
    conn.execute("UPDATE nowave.users SET notifications_enabled = true WHERE id = %s", (ids["user"],))
    conn.execute("UPDATE nowave.devices SET fcm_token = %s WHERE id = %s", (f"test-{ids['device']}", ids["device"]))
    return conn.execute("SELECT installation_id FROM nowave.devices WHERE id = %s", (ids["device"],)).fetchone()[0]


def test_history_is_reused_and_only_selected_installation_is_eligible(db):
    conn, ids = db
    installation = prepare(conn, ids)
    now = datetime.now(UTC)
    with conn.cursor(row_factory=dict_row) as cursor:
        row = load_target(cursor, ids["user"], installation, ids["report"])
        validate_target(row, now, allow_own_report=True)
        first = ensure_history(cursor, row, delivery_for(row, now))
        second = ensure_history(cursor, row, delivery_for(row, now))
        assert first.alert_id == second.alert_id == ids["history"]
        assert first.distance_m == second.distance_m == 18520
        assert load_target(cursor, ids["admin"], installation, ids["report"]) is None
        assert load_target(cursor, ids["user"], uuid4(), ids["report"]) is None


def test_new_history_is_created_once_without_creating_worker_jobs(db):
    conn, ids = db
    installation = prepare(conn, ids)
    before = conn.execute("SELECT count(*) FROM nowave.notifications").fetchone()[0]
    now = datetime.now(UTC)
    with conn.cursor(row_factory=dict_row) as cursor:
        row = load_target(cursor, ids["user"], installation, ids["manual"])
        first = ensure_history(cursor, row, delivery_for(row, now))
        second = ensure_history(cursor, row, delivery_for(row, now))
        assert first.alert_id == second.alert_id
        assert first.report_id == ids["manual"]
        assert first.distance_m == 0
    assert conn.execute("SELECT count(*) FROM nowave.notifications").fetchone()[0] == before
