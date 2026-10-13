from datetime import UTC, datetime, timedelta
from uuid import uuid4

import psycopg
import pytest

from app.infrastructure.repositories.postgresql_alert_recipient_repository import (
    select_alert_recipients,
)
from app.infrastructure.repositories.postgresql_report_repository import PostgreSQLReportRepository
from backend.tests.database.test_publication_alerts import add_device, add_user, publish
from conftest import insert


def position(connection, device_id, distance=1_000, accuracy=50, heading=None):
    connection.execute(
        """
        INSERT INTO nowave.device_positions
            (device_id, position, accuracy_m, heading_deg, measured_at, received_at)
        VALUES (%s, ST_Project('SRID=4326;POINT(5.4 43.31)'::geography, %s, 0),
                %s, %s, now() - interval '1 year', now())
        """,
        (device_id, distance, accuracy, heading),
    )


@pytest.fixture
def selection(dsn):
    with psycopg.connect(dsn) as connection:
        # Other test fixtures share this temporary database; changes roll back.
        connection.execute("UPDATE nowave.users SET notifications_enabled = false")
        author = add_user(connection)
        user = add_user(connection)
        device = add_device(connection, user)
        report = uuid4()
        now = datetime.now(UTC)
        insert(connection, "reports", id=report, author_id=author,
               client_report_id=uuid4(), category="pollution", positioning_mode="manual",
               final_position="SRID=4326;POINT(5.4 43.31)", observed_at=now,
               created_at=now, updated_at=now, expires_at=now + timedelta(hours=24),
               status="active")
        try:
            yield connection, report, author, user, device
        finally:
            connection.rollback()


@pytest.mark.parametrize("distance,expected", [(0, True), (18_519.99, True),
                                             (18_520, True), (18_520.01, False)])
def test_radius_in_metres_is_inclusive(selection, distance, expected):
    connection, report, _, user, device = selection
    position(connection, device, distance)
    recipients = select_alert_recipients(connection.cursor(), report)
    assert bool(recipients) is expected
    if expected:
        assert recipients[0].user_id == user
        assert recipients[0].distance_m == pytest.approx(distance, abs=1e-6)


@pytest.mark.parametrize("accuracy,heading", [(0, None), (50, 180)])
def test_old_position_and_any_heading_are_eligible(selection, accuracy, heading):
    connection, report, _, _, device = selection
    position(connection, device, accuracy=accuracy, heading=heading)
    assert len(select_alert_recipients(connection.cursor(), report)) == 1


@pytest.mark.parametrize("accuracy", [-0.01, 50.01])
def test_database_rejects_unusable_accuracy(selection, accuracy):
    connection, _, _, _, device = selection
    with pytest.raises(psycopg.errors.CheckViolation):
        position(connection, device, accuracy=accuracy)


@pytest.mark.parametrize("change", [
    "UPDATE nowave.users SET notifications_enabled = false WHERE id = %s",
    "UPDATE nowave.users SET status = 'suspended' WHERE id = %s",
    "UPDATE nowave.devices SET is_active = false WHERE user_id = %s",
    "UPDATE nowave.devices SET fcm_token = NULL WHERE user_id = %s",
    "UPDATE nowave.devices SET fcm_token = E' \\t\\n' WHERE user_id = %s",
])
def test_ineligible_recipient_is_excluded(selection, change):
    connection, report, _, user, device = selection
    position(connection, device)
    connection.execute(change, (user,))
    assert select_alert_recipients(connection.cursor(), report) == []


def test_missing_position_is_excluded(selection):
    connection, report, _, _, _ = selection
    assert select_alert_recipients(connection.cursor(), report) == []


def test_nearest_distance_and_distinct_devices_per_user(selection):
    connection, report, author, user, device = selection
    position(connection, device, 5_000)
    nearest = add_device(connection, user)
    position(connection, nearest, 2_000)
    position(connection, add_device(connection, user), 20_000)
    position(connection, add_device(connection, author), 0)
    other = add_user(connection)
    other_device = add_device(connection, other)
    position(connection, other_device, 3_000)

    recipients = {r.user_id: r for r in select_alert_recipients(connection.cursor(), report)}
    assert set(recipients) == {user, other}
    assert set(recipients[user].device_ids) == {device, nearest}
    assert recipients[user].distance_m == pytest.approx(2_000)
    assert recipients[other].device_ids == (other_device,)


@pytest.mark.parametrize("state", ["removed", "expired", "past_expiry", "missing"])
def test_unavailable_report_selects_no_one(selection, state):
    connection, report, _, _, device = selection
    position(connection, device)
    if state == "missing":
        report = uuid4()
    elif state == "past_expiry":
        expired_report = uuid4()
        connection.execute(
            """INSERT INTO nowave.reports
                (id, author_id, client_report_id, category, positioning_mode,
                 final_position, observed_at, created_at, updated_at, expires_at, status)
               SELECT %s, author_id, %s, category, positioning_mode, final_position,
                      now() - interval '2 days', now(), now(), now() - interval '1 day', 'active'
               FROM nowave.reports WHERE id = %s""",
            (expired_report, uuid4(), report),
        )
        report = expired_report
    else:
        connection.execute("UPDATE nowave.reports SET status = %s WHERE id = %s", (state, report))
    assert select_alert_recipients(connection.cursor(), report) == []


@pytest.mark.parametrize("mode", ["manual", "photo"])
def test_real_selection_is_used_by_publication(dsn, monkeypatch, mode):
    monkeypatch.setenv("DATABASE_URL", dsn)
    with psycopg.connect(dsn) as connection:
        author = add_user(connection)
        user = add_user(connection)
        device = add_device(connection, user)
        position(connection, device)
    try:
        report, saved = publish(PostgreSQLReportRepository(), mode, author)
        assert saved is not None
        with psycopg.connect(dsn) as connection:
            rows = connection.execute(
                "SELECT a.distance_m, n.device_id FROM nowave.alert_history a "
                "JOIN nowave.notifications n ON n.report_id = a.report_id "
                "WHERE a.report_id = %s AND a.user_id = %s AND n.device_id = %s",
                (report.id, user, device),
            ).fetchall()
        assert rows == [(pytest.approx(1_000), device)]
    finally:
        with psycopg.connect(dsn) as connection:
            connection.execute("DELETE FROM nowave.users WHERE id = ANY(%s)", ([author, user],))
