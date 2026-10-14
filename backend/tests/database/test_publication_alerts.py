from datetime import UTC, datetime, timedelta
from uuid import uuid4

from fastapi.testclient import TestClient
import psycopg
from psycopg import sql
from psycopg.conninfo import make_conninfo
import pytest

from app.api.dependencies.auth import get_current_identity
from app.application.services.create_report import CreateReport
from app.domain.alert import AlertRecipient
from app.domain.positioning import (
    PositioningMeasurements,
    estimate_position,
)
from app.domain.report import Report, ReportCategory
from app.infrastructure.database.runtime_permissions import (
    grant_runtime_table_permissions,
)
from app.infrastructure.repositories.postgresql_alert_history_repository import (
    PostgreSQLAlertHistoryRepository,
)
from app.infrastructure.repositories.postgresql_report_repository import (
    PostgreSQLReportRepository,
)
from app.infrastructure.repositories.postgresql_user_repository import (
    PostgreSQLUserRepository,
)
from app.main import app
from conftest import insert


MODES = ["manual", "photo"]


class RecordingSelector:
    """Stands in for select_alert_recipients (NW-122)."""

    def __init__(self, dsn, recipients=(), error=None):
        self.dsn = dsn
        self.recipients = list(recipients)
        self.error = error
        self.calls = []

    def __call__(self, cursor, report_id):
        cursor.execute(
            "SELECT status FROM nowave.reports WHERE id = %s",
            (report_id,),
        )
        inside = cursor.fetchone()

        with psycopg.connect(self.dsn) as other:
            outside = other.execute(
                "SELECT status FROM nowave.reports WHERE id = %s",
                (report_id,),
            ).fetchone()

        self.calls.append(
            {
                "report_id": report_id,
                "inside": inside,
                "outside": outside,
            }
        )

        if self.error is not None:
            raise self.error

        return self.recipients


def add_user(connection):
    user_id = uuid4()
    now = datetime.now(UTC)

    insert(
        connection,
        "users",
        id=user_id,
        firebase_uid=f"firebase-{user_id}",
        username=f"alerts-{user_id}",
        email=f"{user_id}@nowave.test",
        role="user",
        status="active",
        notifications_enabled=True,
        created_at=now,
        updated_at=now,
    )

    return user_id


def add_device(connection, user_id):
    device_id = uuid4()

    insert(
        connection,
        "devices",
        id=device_id,
        user_id=user_id,
        installation_id=uuid4(),
        fcm_token=f"token-{device_id}",
        platform="ios",
        is_active=True,
        last_seen_at=datetime.now(UTC),
    )

    return device_id


def create_measurements(captured_at):
    return PositioningMeasurements(
        observer_longitude=5.3779,
        observer_latitude=43.2945,
        gps_accuracy_m=12.0,
        azimuth_deg=145.2,
        inclination_deg=-30.0,
        camera_height_m=2.1,
        camera_height_source="device_estimate",
        camera_height_uncertainty_m=0.1,
        focal_length_mm=24.0,
        zoom_ratio=1.0,
        captured_at=captured_at,
    )


def publish(
    repository,
    mode,
    author_id,
    client_report_id=None,
):
    observed_at = datetime.now(UTC) - timedelta(minutes=5)

    values = {
        "author_id": author_id,
        "client_report_id": client_report_id or uuid4(),
        "category": ReportCategory.MARINE_ANIMAL,
        "longitude": 5.40,
        "latitude": 43.31,
        "observed_at": observed_at,
        "description": None,
    }

    if mode == "manual":
        report = Report.create_manual(**values)

        return report, repository.save(report)

    report = Report.create_photo(**values)
    measurements = create_measurements(observed_at)

    return report, repository.save_photo(
        report=report,
        measurements=measurements,
        estimate=estimate_position(measurements),
    )


def history_rows(connection, report_id):
    return connection.execute(
        """
        SELECT
            id,
            user_id,
            report_version,
            category,
            ST_X(position::geometry),
            ST_Y(position::geometry),
            distance_m,
            alerted_at
        FROM nowave.alert_history
        WHERE report_id = %s
        ORDER BY user_id
        """,
        (report_id,),
    ).fetchall()


def notification_rows(connection, report_id):
    return connection.execute(
        """
        SELECT
            id,
            device_id,
            report_version,
            status,
            attempt_count,
            next_attempt_at,
            sent_at,
            last_error_code,
            created_at,
            updated_at
        FROM nowave.notifications
        WHERE report_id = %s
        ORDER BY device_id
        """,
        (report_id,),
    ).fetchall()


def count_report_rows(connection, report_id):
    return {
        table: connection.execute(
            sql.SQL(
                "SELECT count(*) FROM nowave.{} WHERE {} = %s"
            ).format(
                sql.Identifier(table),
                sql.Identifier(column),
            ),
            (report_id,),
        ).fetchone()[0]
        for table, column in [
            ("reports", "id"),
            ("report_positioning", "report_id"),
            ("report_photos", "report_id"),
            ("alert_history", "report_id"),
            ("notifications", "report_id"),
        ]
    }


@pytest.fixture
def people(dsn, monkeypatch):
    monkeypatch.setenv("DATABASE_URL", dsn)

    with psycopg.connect(dsn, autocommit=True) as connection:
        author_id = add_user(connection)
        first_id = add_user(connection)
        second_id = add_user(connection)

        devices = {
            first_id: sorted(
                [
                    add_device(connection, first_id),
                    add_device(connection, first_id),
                ]
            ),
            second_id: [add_device(connection, second_id)],
        }

    return author_id, first_id, second_id, devices


def recipients_for(people):
    _, first_id, second_id, devices = people

    return [
        AlertRecipient(
            user_id=first_id,
            distance_m=1250.5,
            device_ids=tuple(devices[first_id]),
        ),
        AlertRecipient(
            user_id=second_id,
            distance_m=18520,
            device_ids=tuple(devices[second_id]),
        ),
    ]


@pytest.mark.parametrize("mode", MODES)
def test_publication_writes_alerts_in_its_transaction(
    dsn,
    people,
    mode,
):
    author_id, first_id, second_id, devices = people
    selector = RecordingSelector(dsn, recipients_for(people))
    repository = PostgreSQLReportRepository(
        select_recipients=selector,
    )

    report, saved = publish(repository, mode, author_id)

    assert saved is not None

    # The selection reads the uncommitted report through the
    # publication cursor; other connections cannot see it yet.
    assert selector.calls == [
        {
            "report_id": report.id,
            "inside": ("active",),
            "outside": None,
        },
    ]

    with psycopg.connect(dsn) as connection:
        history = history_rows(connection, report.id)
        notifications = notification_rows(connection, report.id)
        children = count_report_rows(connection, report.id)

    expected_children = 1 if mode == "photo" else 0
    assert children["report_positioning"] == expected_children
    assert children["report_photos"] == expected_children

    instant = saved.created_at

    assert [
        (row[1], row[2], row[3], row[6], row[7])
        for row in history
    ] == sorted(
        [
            (first_id, 1, "marine_animal", 1250.5, instant),
            (second_id, 1, "marine_animal", 18520, instant),
        ]
    )

    for row in history:
        assert row[4] == pytest.approx(5.40)
        assert row[5] == pytest.approx(43.31)

    expected_devices = sorted(
        devices[first_id] + devices[second_id]
    )

    assert [row[1] for row in notifications] == expected_devices

    for row in notifications:
        assert row[2:] == (
            1,
            "pending",
            0,
            instant,
            None,
            None,
            instant,
            instant,
        )

    ids = [row[0] for row in history + notifications]
    assert len(set(ids)) == len(ids)


def test_push_query_of_the_contract_reads_alert_data(
    dsn,
    people,
):
    author_id, first_id, _, devices = people
    repository = PostgreSQLReportRepository(
        select_recipients=RecordingSelector(
            dsn,
            recipients_for(people),
        ),
    )

    report, saved = publish(repository, "manual", author_id)

    with psycopg.connect(dsn) as connection:
        history = {
            row[1]: row[0]
            for row in history_rows(connection, report.id)
        }

        rows = connection.execute(
            """
            SELECT
                d.id,
                a.id AS alert_id,
                a.category,
                a.distance_m,
                r.expires_at,
                d.fcm_token
            FROM nowave.notifications n
            JOIN nowave.devices d ON d.id = n.device_id
            JOIN nowave.alert_history a
              ON a.user_id = d.user_id
             AND a.report_id = n.report_id
             AND a.report_version = n.report_version
            JOIN nowave.reports r ON r.id = n.report_id
            WHERE n.report_id = %s
            ORDER BY d.id
            """,
            (report.id,),
        ).fetchall()

    assert len(rows) == 3

    first_rows = [
        row for row in rows if row[0] in devices[first_id]
    ]

    # Same alert_id and distance on every device of a user.
    assert {row[1] for row in first_rows} == {
        history[first_id]
    }
    assert {row[3] for row in first_rows} == {1250.5}
    assert {row[4] for row in rows} == {saved.expires_at}
    assert all(row[5] == f"token-{row[0]}" for row in rows)


@pytest.mark.parametrize("mode", MODES)
def test_selection_error_rolls_back_the_publication(
    dsn,
    people,
    mode,
):
    author_id = people[0]
    selector = RecordingSelector(
        dsn,
        error=RuntimeError("selection failed"),
    )
    repository = PostgreSQLReportRepository(
        select_recipients=selector,
    )

    with pytest.raises(RuntimeError, match="selection failed"):
        publish(repository, mode, author_id)

    report_id = selector.calls[0]["report_id"]

    with psycopg.connect(dsn) as connection:
        assert set(
            count_report_rows(connection, report_id).values()
        ) == {0}


@pytest.mark.parametrize("mode", MODES)
def test_alert_write_error_rolls_back_the_publication(
    dsn,
    people,
    mode,
):
    author_id, first_id, second_id, devices = people

    # The second recipient points to a device that does not exist:
    # its notification fails after the first history row is written.
    selector = RecordingSelector(
        dsn,
        [
            AlertRecipient(
                user_id=first_id,
                distance_m=10,
                device_ids=tuple(devices[first_id]),
            ),
            AlertRecipient(
                user_id=second_id,
                distance_m=20,
                device_ids=(uuid4(),),
            ),
        ],
    )
    repository = PostgreSQLReportRepository(
        select_recipients=selector,
    )

    with pytest.raises(psycopg.errors.ForeignKeyViolation):
        publish(repository, mode, author_id)

    report_id = selector.calls[0]["report_id"]

    with psycopg.connect(dsn) as connection:
        assert set(
            count_report_rows(connection, report_id).values()
        ) == {0}


@pytest.mark.parametrize("mode", MODES)
def test_replay_creates_no_new_alert(dsn, people, mode):
    author_id = people[0]
    selector = RecordingSelector(dsn, recipients_for(people))

    with psycopg.connect(dsn) as connection:
        firebase_uid = connection.execute(
            "SELECT firebase_uid FROM nowave.users WHERE id = %s",
            (author_id,),
        ).fetchone()[0]

    service = CreateReport(
        user_repository=PostgreSQLUserRepository(),
        report_repository=PostgreSQLReportRepository(
            select_recipients=selector,
        ),
    )

    observed_at = datetime.now(UTC) - timedelta(minutes=5)
    values = {
        "firebase_uid": firebase_uid,
        "client_report_id": uuid4(),
        "category": ReportCategory.POLLUTION,
        "longitude": 5.40,
        "latitude": 43.31,
        "observed_at": observed_at,
        "positioning_mode": mode,
        "positioning": (
            create_measurements(observed_at)
            if mode == "photo"
            else None
        ),
    }

    first = service.execute(**values)
    replay = service.execute(**values)

    assert first.created is True
    assert replay.created is False
    assert replay.report.id == first.report.id
    assert len(selector.calls) == 1

    with psycopg.connect(dsn) as connection:
        counts = count_report_rows(connection, first.report.id)

    assert counts["alert_history"] == 2
    assert counts["notifications"] == 3


def test_conflicting_save_skips_the_selection(dsn, people):
    author_id = people[0]
    selector = RecordingSelector(dsn, recipients_for(people))
    repository = PostgreSQLReportRepository(
        select_recipients=selector,
    )
    client_report_id = uuid4()

    first, saved = publish(
        repository,
        "manual",
        author_id,
        client_report_id,
    )
    second, conflict = publish(
        repository,
        "manual",
        author_id,
        client_report_id,
    )

    assert saved is not None
    assert conflict is None
    assert len(selector.calls) == 1

    with psycopg.connect(dsn) as connection:
        assert count_report_rows(connection, second.id) == {
            "reports": 0,
            "report_positioning": 0,
            "report_photos": 0,
            "alert_history": 0,
            "notifications": 0,
        }


@pytest.mark.parametrize("mode", MODES)
def test_default_selector_requires_a_device_position(dsn, people, mode):
    report, saved = publish(
        PostgreSQLReportRepository(),
        mode,
        people[0],
    )

    assert saved is not None

    with psycopg.connect(dsn) as connection:
        counts = count_report_rows(connection, report.id)

    assert counts["reports"] == 1
    with psycopg.connect(dsn) as connection:
        assert connection.execute(
            "SELECT count(*) FROM nowave.alert_history WHERE report_id = %s AND user_id = ANY(%s)",
            (report.id, [people[1], people[2]]),
        ).fetchone()[0] == 0


def test_history_is_paged_newest_first_per_user(dsn, people):
    author_id, first_id, second_id, _ = people
    now = datetime.now(UTC)

    with psycopg.connect(dsn, autocommit=True) as connection:
        report_id = connection.execute(
            """
            INSERT INTO nowave.reports (
                id, author_id, client_report_id, category,
                positioning_mode, final_position, observed_at,
                created_at, expires_at, status, updated_at
            )
            VALUES (
                %s, %s, %s, 'pollution', 'manual',
                'SRID=4326;POINT(5 43)', %s, %s, %s,
                'active', %s
            )
            RETURNING id
            """,
            (
                uuid4(),
                author_id,
                uuid4(),
                now,
                now,
                now + timedelta(hours=24),
                now,
            ),
        ).fetchone()[0]

        def add_alert(user_id, version, alerted_at, alert_id=None):
            alert_id = alert_id or uuid4()

            insert(
                connection,
                "alert_history",
                id=alert_id,
                user_id=user_id,
                report_id=report_id,
                report_version=version,
                category="obstruction",
                position=f"SRID=4326;POINT({version} 4{version})",
                distance_m=100 * version,
                alerted_at=alerted_at,
            )

            return alert_id

        oldest = add_alert(first_id, 1, now - timedelta(hours=2))
        tied = sorted([uuid4(), uuid4()])
        add_alert(first_id, 2, now - timedelta(hours=1), tied[0])
        add_alert(first_id, 3, now - timedelta(hours=1), tied[1])
        add_alert(second_id, 1, now)

    repository = PostgreSQLAlertHistoryRepository()

    first_page = repository.list_for_user(
        user_id=first_id,
        page=1,
        limit=2,
    )
    second_page = repository.list_for_user(
        user_id=first_id,
        page=2,
        limit=2,
    )

    assert (first_page.total, first_page.pages) == (3, 2)
    assert [item.id for item in first_page.items] == [
        tied[1],
        tied[0],
    ]
    assert [item.id for item in second_page.items] == [oldest]
    assert second_page.total == 3

    newest = first_page.items[0]
    assert newest.report_id == report_id
    assert newest.report_version == 3
    assert newest.category == ReportCategory.OBSTRUCTION
    assert newest.longitude == pytest.approx(3)
    assert newest.latitude == pytest.approx(43)
    assert newest.distance_m == 300

    other = repository.list_for_user(
        user_id=second_id,
        page=1,
        limit=20,
    )

    assert other.total == 1
    assert repository.list_for_user(
        user_id=author_id,
        page=1,
        limit=20,
    ).items == []


def test_history_survives_failed_and_purged_pushes(dsn, people):
    author_id, first_id, _, _ = people
    repository = PostgreSQLReportRepository(
        select_recipients=RecordingSelector(
            dsn,
            recipients_for(people),
        ),
    )

    report, _ = publish(repository, "manual", author_id)

    with psycopg.connect(dsn, autocommit=True) as connection:
        connection.execute(
            """
            UPDATE nowave.notifications
            SET status = 'failed', last_error_code = 'unregistered'
            WHERE report_id = %s
            """,
            (report.id,),
        )
        connection.execute(
            "DELETE FROM nowave.notifications WHERE report_id = %s",
            (report.id,),
        )

    history = PostgreSQLAlertHistoryRepository().list_for_user(
        user_id=first_id,
        page=1,
        limit=20,
    )

    assert [item.report_id for item in history.items] == [
        report.id
    ]


def test_publication_and_history_work_with_runtime_role(
    dsn,
    people,
    monkeypatch,
):
    author_id, first_id, _, devices = people
    device_id = devices[first_id][0]

    with psycopg.connect(dsn) as connection:
        uids = dict(
            connection.execute(
                """
                SELECT id, firebase_uid
                FROM nowave.users
                WHERE id = ANY(%s)
                """,
                ([author_id, first_id],),
            ).fetchall()
        )

    calls = []

    def select_recipients(cursor, report_id):
        cursor.execute(
            "SELECT author_id FROM nowave.reports WHERE id = %s",
            (report_id,),
        )
        assert cursor.fetchone()[0] == author_id

        calls.append(report_id)

        return [
            AlertRecipient(
                user_id=first_id,
                distance_m=1200.0,
                device_ids=(device_id,),
            ),
        ]

    monkeypatch.setattr(
        "app.api.routes.reports.PostgreSQLReportRepository",
        lambda: PostgreSQLReportRepository(
            select_recipients=select_recipients,
        ),
    )

    role_name = "nw118_runtime_" + uuid4().hex
    role = sql.Identifier(role_name)

    with psycopg.connect(dsn, autocommit=True) as admin:
        admin.execute(
            sql.SQL(
                "CREATE ROLE {} "
                "NOSUPERUSER NOCREATEDB NOCREATEROLE"
            ).format(role)
        )

        try:
            grant_runtime_table_permissions(admin, role_name)

            runtime_dsn = make_conninfo(
                dsn,
                options=f"-c role={role_name}",
            )
            monkeypatch.setenv("DATABASE_URL", runtime_dsn)

            client = TestClient(app)

            app.dependency_overrides[get_current_identity] = (
                lambda: {"uid": uids[author_id]}
            )

            body = {
                "client_report_id": str(uuid4()),
                "category": "marine_animal",
                "final_position": {
                    "type": "Point",
                    "coordinates": [5.40, 43.31],
                },
                "observed_at": (
                    datetime.now(UTC) - timedelta(minutes=5)
                ).isoformat(),
            }

            created = client.post("/api/v1/reports", json=body)
            replay = client.post("/api/v1/reports", json=body)

            assert created.status_code == 201
            assert replay.status_code == 200
            assert len(calls) == 1

            app.dependency_overrides[get_current_identity] = (
                lambda: {"uid": uids[first_id]}
            )

            response = client.get("/api/v1/users/me/alerts")

            assert response.status_code == 200

            page = response.json()
            item = page["items"][0]

            assert (page["total"], page["page"]) == (1, 1)
            assert item["report_id"] == created.json()["id"]
            assert item["report_version"] == 1
            assert item["category"] == "marine_animal"
            assert item["position"]["coordinates"] == pytest.approx(
                [5.40, 43.31]
            )
            assert item["distance_m"] == 1200.0

            def privilege(table, action):
                return admin.execute(
                    "SELECT has_table_privilege(%s, %s, %s)",
                    (role_name, f"nowave.{table}", action),
                ).fetchone()[0]

            assert privilege("notifications", "INSERT")
            assert privilege("alert_history", "INSERT")
            assert not privilege("alert_history", "UPDATE")
            assert not privilege("alert_history", "DELETE")

            # Account deletion still removes the history (cascade).
            with psycopg.connect(runtime_dsn) as runtime:
                runtime.execute(
                    "DELETE FROM nowave.users WHERE id = %s",
                    (first_id,),
                )

            remaining = admin.execute(
                """
                SELECT count(*)
                FROM nowave.alert_history
                WHERE user_id = %s
                """,
                (first_id,),
            ).fetchone()[0]

            assert remaining == 0

        finally:
            app.dependency_overrides.clear()

            admin.execute(
                sql.SQL("DROP OWNED BY {}").format(role)
            )
            admin.execute(
                sql.SQL("DROP ROLE {}").format(role)
            )
