from concurrent.futures import ThreadPoolExecutor
from contextlib import contextmanager
from datetime import UTC, datetime
from threading import Event
from time import monotonic, sleep
from uuid import uuid4

from fastapi.testclient import TestClient
import psycopg
import pytest

from app.api.dependencies.auth import get_authenticated_identity
from app.infrastructure.repositories import postgresql_device_repository
from app.infrastructure.repositories.postgresql_device_repository import (
    PostgreSQLDeviceRepository,
)
from app.main import app


@pytest.fixture(params=[False, True], ids=["first-position", "existing-position"])
def device_requests(db, dsn, monkeypatch, request):
    connection, ids = db
    monkeypatch.setenv("DATABASE_URL", dsn)
    last_seen_at = datetime(2026, 1, 1, tzinfo=UTC)
    installation_id = connection.execute(
        """
        UPDATE nowave.devices
        SET fcm_token = %s, last_seen_at = %s
        WHERE id = %s
        RETURNING installation_id
        """,
        (f"t03-{uuid4()}", last_seen_at, ids["device"]),
    ).fetchone()[0]
    if not request.param:
        connection.execute(
            "DELETE FROM nowave.device_positions WHERE device_id = %s",
            (ids["device"],),
        )
    uid = connection.execute(
        "SELECT firebase_uid FROM nowave.users WHERE id = %s", (ids["user"],)
    ).fetchone()[0]
    connection.commit()

    headers = {"X-Installation-ID": str(installation_id)}
    payload = {
        "position": {"type": "Point", "coordinates": [5.37, 43.29]},
        "accuracy_m": 18,
        "measured_at": datetime.now(UTC).isoformat(),
    }
    # Both routes share authentication; PUT also checks the real user's status.
    monkeypatch.setitem(
        app.dependency_overrides,
        get_authenticated_identity,
        lambda: {"uid": uid, "email_verified": True},
    )

    def put():
        with TestClient(app) as client:
            return client.put(
                "/api/v1/devices/current/position", headers=headers, json=payload
            )

    def delete():
        with TestClient(app) as client:
            return client.delete("/api/v1/devices/current", headers=headers)

    return put, delete, last_seen_at


def assert_deactivated(db, last_seen_at):
    connection, ids = db
    assert connection.execute(
        """
        SELECT is_active, fcm_token, last_seen_at
        FROM nowave.devices WHERE id = %s
        """,
        (ids["device"],),
    ).fetchone() == (False, None, last_seen_at)
    assert connection.execute(
        "SELECT count(*) FROM nowave.device_positions WHERE device_id = %s",
        (ids["device"],),
    ).fetchone()[0] == 0
    assert connection.execute(
        """
        SELECT count(*) FROM nowave.notifications
        WHERE device_id = %s AND status = 'pending'
        """,
        (ids["device"],),
    ).fetchone()[0] == 0


@contextmanager
def pause_before_statement(monkeypatch, prefix):
    """Pause a real transaction, retaining its locks, before the next write."""
    entered, release = Event(), Event()
    holder = {}
    original_connection = postgresql_device_repository.database_connection

    class PausingCursor(psycopg.Cursor):
        def execute(self, query, params=None, **kwargs):
            if " ".join(query.split()).startswith(prefix):
                holder["pid"] = self.connection.info.backend_pid
                entered.set()
                assert release.wait(10), "Transaction was not released"
            return super().execute(query, params, **kwargs)

    @contextmanager
    def controlled_connection():
        with original_connection() as connection:
            connection.execute("SET LOCAL statement_timeout = '10s'")
            connection.cursor_factory = PausingCursor
            yield connection

    with monkeypatch.context() as patch:
        patch.setattr(
            postgresql_device_repository, "database_connection", controlled_connection
        )
        try:
            yield entered, holder
        finally:
            release.set()


def wait_for_blocked_transaction(dsn, holder_pid):
    """Check PostgreSQL's actual wait graph instead of relying on timing."""
    with psycopg.connect(dsn, autocommit=True) as observer:
        deadline = monotonic() + 5
        while monotonic() < deadline:
            blocked = observer.execute(
                """
                SELECT EXISTS (
                    SELECT 1 FROM pg_stat_activity
                    WHERE %s = ANY(pg_blocking_pids(pid))
                )
                """,
                (holder_pid,),
            ).fetchone()[0]
            if blocked:
                return
            sleep(0.01)
    pytest.fail("The competing transaction did not wait for the device lock")


def test_put_started_before_delete_cannot_restore_position(
    db, device_requests, monkeypatch
):
    put, delete, last_seen_at = device_requests
    checked, release = Event(), Event()
    original_save = PostgreSQLDeviceRepository.save_position

    def delayed_save(self, position):
        # The service has already fetched an active device in another transaction.
        checked.set()
        assert release.wait(10), "Position request was not released"
        return original_save(self, position)

    monkeypatch.setattr(PostgreSQLDeviceRepository, "save_position", delayed_save)
    with ThreadPoolExecutor(max_workers=1) as pool:
        pending_put = pool.submit(put)
        try:
            assert checked.wait(5)
            assert delete().status_code == 204
            assert_deactivated(db, last_seen_at)
        finally:
            release.set()
        response = pending_put.result(timeout=10)

    assert response.status_code == 404
    assert response.json()["error"]["code"] == "device_not_found"
    assert_deactivated(db, last_seen_at)


def test_delete_waits_for_put_then_cleans_its_position(
    db, dsn, device_requests, monkeypatch
):
    put, delete, _ = device_requests
    with ThreadPoolExecutor(max_workers=2) as pool:
        with pause_before_statement(
            monkeypatch, "INSERT INTO nowave.device_positions"
        ) as (entered, holder):
            pending_put = pool.submit(put)
            assert entered.wait(5)
            pending_delete = pool.submit(delete)
            wait_for_blocked_transaction(dsn, holder["pid"])

        response = pending_put.result(timeout=10)
        assert response.status_code == 200
        assert pending_delete.result(timeout=10).status_code == 204

    assert_deactivated(db, datetime.fromisoformat(response.json()["received_at"]))


def test_put_waits_for_delete_then_rejects_inactive_device(
    db, dsn, device_requests, monkeypatch
):
    put, delete, last_seen_at = device_requests
    with ThreadPoolExecutor(max_workers=2) as pool:
        with pause_before_statement(
            monkeypatch, "SELECT id FROM nowave.notifications"
        ) as (entered, holder):
            pending_delete = pool.submit(delete)
            assert entered.wait(5)
            pending_put = pool.submit(put)
            wait_for_blocked_transaction(dsn, holder["pid"])

        assert pending_delete.result(timeout=10).status_code == 204
        response = pending_put.result(timeout=10)

    assert response.status_code == 404
    assert response.json()["error"]["code"] == "device_not_found"
    assert_deactivated(db, last_seen_at)
