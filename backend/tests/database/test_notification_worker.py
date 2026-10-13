from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, datetime, timedelta
from threading import Event
from uuid import uuid4
from types import SimpleNamespace
import json
import os
import subprocess
import sys
import select
from time import monotonic, sleep

import httpx
import psycopg
from psycopg import sql
from psycopg.conninfo import make_conninfo
import pytest

from app.application.services.send_notifications import SendNotifications
from app.domain.notification import PushSendError
from app.infrastructure.adapters.firebase_push_sender import FirebasePushSender
from app.infrastructure.database.runtime_permissions import (
    grant_runtime_table_permissions,
)
from app.infrastructure.repositories.postgresql_device_repository import (
    PostgreSQLDeviceRepository,
)
from app.infrastructure.repositories.postgresql_notification_repository import (
    PostgreSQLNotificationRepository,
)
from app.infrastructure.repositories.postgresql_report_repository import (
    PostgreSQLReportRepository,
)
from backend.tests.database.test_publication_alerts import add_device, add_user, publish
from backend.tests.database.test_alert_recipient_repository import position
from backend.tests.notification_helpers import RecordingPushSender
from conftest import insert


@pytest.fixture
def jobs(dsn, monkeypatch):
    monkeypatch.setenv("DATABASE_URL", dsn)
    created = []

    def create(*, expires_at=None, commit=True):
        now = datetime.now(UTC)
        expires_at = expires_at or now + timedelta(hours=24)
        connection = psycopg.connect(dsn)
        author = add_user(connection)
        user = add_user(connection)
        device = add_device(connection, user)
        report, alert, notification = uuid4(), uuid4(), uuid4()
        insert(
            connection,
            "reports",
            id=report,
            author_id=author,
            client_report_id=uuid4(),
            category="pollution",
            positioning_mode="manual",
            final_position="SRID=4326;POINT(5.4 43.31)",
            observed_at=expires_at - timedelta(hours=24),
            expires_at=expires_at,
            created_at=now,
            updated_at=now,
            status="active",
        )
        insert(
            connection,
            "alert_history",
            id=alert,
            user_id=user,
            report_id=report,
            report_version=1,
            category="pollution",
            position="SRID=4326;POINT(5.4 43.31)",
            distance_m=1_000,
            alerted_at=now,
        )
        insert(
            connection,
            "notifications",
            id=notification,
            report_id=report,
            device_id=device,
            report_version=1,
            status="pending",
            next_attempt_at=now,
            created_at=now,
            updated_at=now,
        )
        job = dict(
            author=author,
            user=user,
            device=device,
            report=report,
            alert=alert,
            notification=notification,
            connection=connection,
        )
        created.append(job)
        if commit:
            connection.commit()
        return job

    yield create
    for job in created:
        job["connection"].rollback()
        job["connection"].close()
        with psycopg.connect(dsn) as connection:
            connection.execute(
                "DELETE FROM nowave.reports WHERE id = %s", (job["report"],)
            )
            connection.execute(
                "DELETE FROM nowave.users WHERE id = ANY(%s)",
                ([job["user"], job["author"]],),
            )


def repository_for(job):
    repository = PostgreSQLNotificationRepository()
    # Isolate this worker's queue from unrelated fixtures in the shared test DB.
    repository.due_ids = lambda: [job["notification"]]
    return repository


def state(job):
    return (
        job["connection"]
        .execute(
            "SELECT status, attempt_count, next_attempt_at, sent_at, last_error_code "
            "FROM nowave.notifications WHERE id = %s",
            (job["notification"],),
        )
        .fetchone()
    )


def test_only_committed_tasks_are_visible(jobs):
    job = jobs(commit=False)
    repository = PostgreSQLNotificationRepository()
    assert job["notification"] not in repository.due_ids(limit=10000)
    sender = RecordingPushSender()
    assert SendNotifications(repository_for(job), sender).run_once() == 0
    job["connection"].commit()
    assert job["notification"] in repository.due_ids(limit=10000)
    assert SendNotifications(repository_for(job), sender).run_once() == 1


def test_success_uses_current_token_and_history_uuid(jobs):
    job = jobs()
    job["connection"].execute(
        "UPDATE nowave.devices SET fcm_token = 'rotated-token' WHERE id = %s",
        (job["device"],),
    )
    job["connection"].commit()
    sender = RecordingPushSender()
    service = SendNotifications(repository_for(job), sender)
    assert service.run_once() == 1
    assert service.run_once() == 0
    message = sender.deliveries[0]
    assert message.fcm_token == "rotated-token"
    assert message.alert_id == job["alert"]
    assert message.notification_id == job["notification"]
    assert state(job)[:3] == ("sent", 1, None)
    assert state(job)[3] is not None


@pytest.mark.parametrize(
    "table,field,value,key,reason",
    [
        ("users", "status", "suspended", "user", "user_inactive"),
        ("users", "notifications_enabled", False, "user", "consent_revoked"),
        ("devices", "is_active", False, "device", "device_inactive"),
        ("devices", "fcm_token", None, "device", "device_token_missing"),
        ("reports", "status", "removed", "report", "report_not_visible"),
        ("reports", "version", 2, "report", "report_version_changed"),
    ],
)
def test_eligibility_is_checked_again_before_send(
    jobs, table, field, value, key, reason
):
    job = jobs()
    job["connection"].execute(
        sql.SQL("UPDATE nowave.{} SET {} = %s WHERE id = %s").format(
            sql.Identifier(table), sql.Identifier(field)
        ),
        (value, job[key]),
    )
    job["connection"].commit()
    sender = RecordingPushSender()
    assert SendNotifications(repository_for(job), sender).run_once() == 0
    assert sender.deliveries == []
    assert state(job)[0:2] == ("failed", 0)
    assert state(job)[4] == reason


def test_expiration_overrides_future_retry(jobs):
    job = jobs(expires_at=datetime.now(UTC) - timedelta(seconds=1))
    job["connection"].execute(
        "UPDATE nowave.notifications SET next_attempt_at = now() + interval '1 hour' "
        "WHERE id = %s",
        (job["notification"],),
    )
    job["connection"].commit()
    assert job["notification"] in PostgreSQLNotificationRepository().due_ids(
        limit=10000
    )
    sender = RecordingPushSender()
    SendNotifications(repository_for(job), sender).run_once()
    assert state(job)[4] == "report_expired"
    assert sender.deliveries == []


def test_missing_history_never_sends(jobs):
    job = jobs()
    job["connection"].execute(
        "DELETE FROM nowave.alert_history WHERE id = %s", (job["alert"],)
    )
    job["connection"].commit()
    sender = RecordingPushSender()
    SendNotifications(repository_for(job), sender).run_once()
    assert state(job)[4] == "alert_history_missing"
    assert sender.deliveries == []


@pytest.mark.parametrize(
    "attempt,minutes", [(0, 1), (1, 5), (2, 15), (3, 30), (4, 60), (8, 60)]
)
def test_retry_is_persisted_and_not_sent_early(jobs, attempt, minutes):
    job = jobs()
    job["connection"].execute(
        "UPDATE nowave.notifications SET attempt_count = %s WHERE id = %s",
        (attempt, job["notification"]),
    )
    job["connection"].commit()
    now = datetime.now(UTC)
    sender = RecordingPushSender(PushSendError("fcm_network"))
    worker = SendNotifications(repository_for(job), sender, clock=lambda: now)
    worker.run_once()
    assert state(job)[:3] == ("pending", attempt + 1, now + timedelta(minutes=minutes))
    worker.run_once()
    assert len(sender.deliveries) == 1


def test_retry_after_and_expiration_limit(jobs):
    job = jobs(expires_at=datetime.now(UTC) + timedelta(minutes=30))
    now = datetime.now(UTC)
    sender = RecordingPushSender(
        PushSendError("fcm_unavailable", retry_after=now + timedelta(hours=1))
    )
    SendNotifications(repository_for(job), sender).run_once()
    assert state(job)[:3] == ("failed", 1, None)
    assert state(job)[4] == "retry_after_expiry"


def test_longer_retry_after_is_stored(jobs):
    job = jobs()
    scheduled = datetime.now(UTC) + timedelta(hours=2)
    sender = RecordingPushSender(
        PushSendError("fcm_unavailable", retry_after=scheduled)
    )
    SendNotifications(repository_for(job), sender).run_once()
    assert state(job)[2] == scheduled


@pytest.mark.parametrize("invalid", [False, True])
def test_permanent_error_only_clears_explicitly_invalid_token(jobs, invalid):
    job = jobs()
    sender = RecordingPushSender(
        PushSendError(
            "fcm_unregistered" if invalid else "fcm_invalid_request",
            permanent=True,
            invalid_token=invalid,
        )
    )
    SendNotifications(repository_for(job), sender).run_once()
    assert state(job)[:3] == ("failed", 1, None)
    token = (
        job["connection"]
        .execute("SELECT fcm_token FROM nowave.devices WHERE id = %s", (job["device"],))
        .fetchone()[0]
    )
    assert (token is None) is invalid
    assert (
        job["connection"]
        .execute(
            "SELECT count(*) FROM nowave.alert_history WHERE id = %s", (job["alert"],)
        )
        .fetchone()[0]
        == 1
    )


def test_two_workers_do_not_send_the_same_task_concurrently(jobs):
    job = jobs()
    entered, release = Event(), Event()

    class BlockingSender(RecordingPushSender):
        def send(self, delivery, now):
            entered.set()
            assert release.wait(5)
            return super().send(delivery, now)

    first, second = BlockingSender(), RecordingPushSender()
    with ThreadPoolExecutor(max_workers=2) as executor:
        future = executor.submit(SendNotifications(repository_for(job), first).run_once)
        try:
            assert entered.wait(5)
            assert (
                executor.submit(
                    SendNotifications(repository_for(job), second).run_once
                ).result(3)
                == 0
            )
        finally:
            release.set()
        assert future.result(5) == 1
    assert len(first.deliveries) == 1
    assert second.deliveries == []


@pytest.mark.parametrize(
    "table,key", [("users", "user"), ("reports", "report"), ("devices", "device")]
)
def test_busy_parent_is_skipped_without_blocking(jobs, table, key):
    job = jobs()
    job["connection"].execute(
        sql.SQL("SELECT id FROM nowave.{} WHERE id = %s FOR UPDATE").format(
            sql.Identifier(table)
        ),
        (job[key],),
    )
    sender = RecordingPushSender()
    with ThreadPoolExecutor(max_workers=1) as executor:
        assert (
            executor.submit(
                SendNotifications(repository_for(job), sender).run_once
            ).result(3)
            == 0
        )
    job["connection"].rollback()
    assert SendNotifications(repository_for(job), sender).run_once() == 1


def test_device_deactivation_before_worker_discards_pending_task(jobs):
    job = jobs()
    installation = (
        job["connection"]
        .execute(
            "SELECT installation_id FROM nowave.devices WHERE id = %s", (job["device"],)
        )
        .fetchone()[0]
    )
    assert PostgreSQLDeviceRepository().deactivate(job["user"], installation)
    sender = RecordingPushSender()
    SendNotifications(repository_for(job), sender).run_once()
    assert sender.deliveries == []
    assert state(job) is None


def test_restart_after_acceptance_before_commit_keeps_stable_ids(jobs):
    job = jobs()
    crashed = RecordingPushSender(
        SystemExit("simulated process death after acceptance")
    )
    with pytest.raises(SystemExit):
        SendNotifications(repository_for(job), crashed).run_once()
    assert state(job)[:2] == ("pending", 0)
    restarted = RecordingPushSender()
    assert SendNotifications(repository_for(job), restarted).run_once() == 1
    assert crashed.deliveries[0].data() == restarted.deliveries[0].data()


@pytest.mark.parametrize("old_status", ["sent", "failed"])
def test_purge_uses_terminal_time_and_keeps_history(jobs, old_status):
    old = jobs()
    recent = jobs()
    pending = jobs()
    for job, status, age in [
        (old, old_status, 8),
        (recent, "failed", 6),
        (pending, "pending", 8),
    ]:
        job["connection"].execute(
            "UPDATE nowave.notifications SET status = %s, created_at = now() - interval '20 days', "
            "sent_at = now() - interval '8 days', updated_at = now() - %s * interval '1 day' WHERE id = %s",
            (status, age, job["notification"]),
        )
        job["connection"].commit()
    PostgreSQLNotificationRepository().purge()
    assert state(old) is None
    assert state(recent)[0] == "failed"
    assert state(pending)[0] == "pending"
    assert (
        old["connection"]
        .execute(
            "SELECT count(*) FROM nowave.alert_history WHERE id = %s", (old["alert"],)
        )
        .fetchone()[0]
        == 1
    )


def test_expiry_cleanup_does_not_need_fcm_credentials(jobs):
    expired = jobs(expires_at=datetime.now(UTC) - timedelta(seconds=1))
    active = jobs()
    PostgreSQLNotificationRepository().expire_pending()
    assert state(expired)[4] == "report_expired"
    assert state(active)[0] == "pending"


@pytest.mark.parametrize(
    "table,key,assignment",
    [
        ("users", "user", "notifications_enabled = false"),
        ("users", "user", "status = 'suspended'"),
        ("reports", "report", "status = 'removed'"),
        ("devices", "device", "is_active = false"),
    ],
)
def test_eligibility_cannot_change_between_check_and_send(
    jobs, dsn, table, key, assignment
):
    job = jobs()
    entered, release = Event(), Event()

    class BlockingSender(RecordingPushSender):
        def send(self, delivery, now):
            entered.set()
            assert release.wait(5)
            return super().send(delivery, now)

    with ThreadPoolExecutor(max_workers=1) as executor:
        future = executor.submit(
            SendNotifications(repository_for(job), BlockingSender()).run_once
        )
        try:
            assert entered.wait(5)
            with psycopg.connect(dsn) as connection:
                connection.execute("SET LOCAL lock_timeout = '150ms'")
                with pytest.raises(psycopg.errors.LockNotAvailable):
                    connection.execute(
                        sql.SQL("UPDATE nowave.{} SET {} WHERE id = %s").format(
                            sql.Identifier(table), sql.SQL(assignment)
                        ),
                        (job[key],),
                    )
                connection.rollback()
        finally:
            release.set()
        assert future.result(5) == 1


def test_failure_before_acceptance_rolls_back_and_next_worker_recovers(jobs):
    job = jobs()

    class InterruptedSender(RecordingPushSender):
        def send(self, delivery, now):
            raise SystemExit("simulated crash before sending")

    with pytest.raises(SystemExit):
        SendNotifications(repository_for(job), InterruptedSender()).run_once()
    assert state(job)[:2] == ("pending", 0)
    assert SendNotifications(repository_for(job), RecordingPushSender()).run_once() == 1


def test_worker_respects_stop_between_tasks(jobs):
    job = jobs()
    stop = Event()
    stop.set()
    sender = RecordingPushSender()
    assert SendNotifications(repository_for(job), sender).run_once(stop=stop) == 0
    assert sender.deliveries == []
    assert state(job)[0] == "pending"


def test_worker_works_with_runtime_permissions(jobs, dsn, monkeypatch):
    job = jobs()
    role_name = "nw123_runtime_" + uuid4().hex
    role = sql.Identifier(role_name)
    with psycopg.connect(dsn, autocommit=True) as admin:
        admin.execute(
            sql.SQL("CREATE ROLE {} NOSUPERUSER NOCREATEDB NOCREATEROLE").format(role)
        )
        try:
            grant_runtime_table_permissions(admin, role_name)
            monkeypatch.setenv(
                "DATABASE_URL", make_conninfo(dsn, options=f"-c role={role_name}")
            )
            repository = repository_for(job)
            assert SendNotifications(repository, RecordingPushSender()).run_once() == 1
            repository.expire_pending()
            repository.purge()
            assert state(job)[0] == "sent"
        finally:
            admin.execute(sql.SQL("DROP OWNED BY {}").format(role))
            admin.execute(sql.SQL("DROP ROLE {}").format(role))


@pytest.mark.parametrize("mode", ["manual", "photo"])
def test_publication_to_fcm_with_retry_and_shared_history(dsn, monkeypatch, mode):
    monkeypatch.setenv("DATABASE_URL", dsn)
    with psycopg.connect(dsn) as connection:
        author, user = add_user(connection), add_user(connection)
        devices = [add_device(connection, user), add_device(connection, user)]
        for device in devices:
            position(connection, device)
    received = []

    def fcm(request):
        received.append(json.loads(request.content)["message"])
        if len(received) == 1:
            return httpx.Response(
                503, headers={"Retry-After": "120"}, json={"error": {}}
            )
        return httpx.Response(200, json={"name": "projects/test/messages/accepted"})

    sender = FirebasePushSender(
        SimpleNamespace(valid=True, token="test-access-token"),
        "test",
        client=httpx.Client(transport=httpx.MockTransport(fcm)),
    )
    report = None
    try:
        report, _ = publish(PostgreSQLReportRepository(), mode, author)
        with psycopg.connect(dsn) as connection:
            ids = [
                row[0]
                for row in connection.execute(
                    "SELECT id FROM nowave.notifications WHERE report_id = %s AND device_id = ANY(%s)",
                    (report.id, devices),
                )
            ]
        assert len(ids) == 2
        repository = PostgreSQLNotificationRepository()
        repository.due_ids = lambda: ids
        worker = SendNotifications(repository, sender)
        assert worker.run_once() == 1
        with psycopg.connect(dsn) as connection:
            pending = connection.execute(
                "SELECT id, next_attempt_at FROM nowave.notifications WHERE id = ANY(%s) AND status = 'pending'",
                (ids,),
            ).fetchone()
            assert pending[1] > datetime.now(UTC) + timedelta(seconds=110)
            connection.execute(
                "UPDATE nowave.notifications SET next_attempt_at = now() WHERE id = %s",
                (pending[0],),
            )
        assert worker.run_once() == 1
        assert len(received) == 3
        assert received[0]["data"] == received[2]["data"]
        assert len({message["data"]["alert_id"] for message in received}) == 1
        with psycopg.connect(dsn) as connection:
            assert (
                connection.execute(
                    "SELECT count(*) FROM nowave.alert_history WHERE report_id = %s AND user_id = %s",
                    (report.id, user),
                ).fetchone()[0]
                == 1
            )
    finally:
        sender.close()
        with psycopg.connect(dsn) as connection:
            if report:
                connection.execute(
                    "DELETE FROM nowave.reports WHERE id = %s", (report.id,)
                )
            connection.execute(
                "DELETE FROM nowave.users WHERE id = ANY(%s)", ([author, user],)
            )


def test_killed_process_releases_locks_and_reuses_delivery_identity(jobs, tmp_path):
    job = jobs()
    marker = tmp_path / "accepted.json"
    code = """
import json, os, signal
from pathlib import Path
from uuid import UUID
from app.application.services.send_notifications import SendNotifications
from app.infrastructure.repositories.postgresql_notification_repository import PostgreSQLNotificationRepository

class Sender:
    def prepare(self):
        pass
    def send(self, delivery, now):
        Path(os.environ['TEST_ACCEPTED_PATH']).write_text(json.dumps(delivery.data()))
        os.kill(os.getpid(), signal.SIGKILL)

repository = PostgreSQLNotificationRepository()
repository.due_ids = lambda: [UUID(os.environ['TEST_NOTIFICATION_ID'])]
SendNotifications(repository, Sender()).run_once()
"""
    child = subprocess.run(
        [sys.executable, "-c", code],
        env={
            **os.environ,
            "TEST_ACCEPTED_PATH": str(marker),
            "TEST_NOTIFICATION_ID": str(job["notification"]),
        },
        capture_output=True,
        timeout=10,
    )
    assert child.returncode == -9
    accepted_data = json.loads(marker.read_text())
    sender = RecordingPushSender()
    deadline = monotonic() + 3
    while monotonic() < deadline:
        if SendNotifications(repository_for(job), sender).run_once():
            break
        sleep(0.02)
    assert len(sender.deliveries) == 1
    assert sender.deliveries[0].data() == accepted_data
    assert state(job)[:2] == ("sent", 1)


def test_stop_during_credential_preparation_does_not_start_a_send(jobs):
    job = jobs()
    stop = Event()
    sender = RecordingPushSender()
    sender.prepare = stop.set
    assert SendNotifications(repository_for(job), sender).run_once(stop=stop) == 0
    assert sender.deliveries == []
    assert state(job)[0] == "pending"


def test_worker_handles_missing_credentials_and_sigterm(jobs, tmp_path):
    job = jobs()
    child = subprocess.Popen(
        [sys.executable, "-m", "app.workers.notifications"],
        env={
            **os.environ,
            "GOOGLE_APPLICATION_CREDENTIALS": str(
                tmp_path / "missing-credentials.json"
            ),
            "GOOGLE_CLOUD_PROJECT": "test-project",
        },
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    try:
        readable, _, _ = select.select([child.stderr], [], [], 5)
        assert readable
        assert b"fcm_configuration" in child.stderr.readline()
        child.terminate()
        child.communicate(timeout=5)
        assert child.returncode == 0
        assert state(job)[0] == "pending"
    finally:
        if child.poll() is None:
            child.kill()
            child.communicate(timeout=5)
