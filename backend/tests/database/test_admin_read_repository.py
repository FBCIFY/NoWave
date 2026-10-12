from datetime import UTC, datetime, timedelta
from uuid import uuid4

import psycopg
from psycopg import sql
from psycopg.conninfo import make_conninfo

from app.domain.moderation import ModerationActionType
from app.domain.report import ReportStatus
from app.domain.report_photo import UploadStatus
from app.domain.user import UserRole, UserStatus
from app.infrastructure.database.runtime_permissions import (
    grant_runtime_table_permissions,
)
from app.infrastructure.repositories.postgresql_admin_read_repository import (
    PostgreSQLAdminReadRepository,
)


def repository_for_test(
    dsn,
    monkeypatch,
):
    monkeypatch.setenv(
        "DATABASE_URL",
        dsn,
    )

    return PostgreSQLAdminReadRepository()


def read_all(read_page):
    """Walk every page. The shared test database also holds the rows of
    other tests, so a seeded row can be on any page."""
    items = []
    page = 1

    while True:
        result = read_page(page)
        items.extend(result.items)

        if page >= result.pages:
            assert len(items) == result.total
            return items

        page += 1


def insert_expired_active_report(connection, author_id):
    """No job rewrites the status: the row stays active after expiry."""
    observed_at = datetime.now(UTC) - timedelta(hours=30)
    report_id = uuid4()

    connection.execute(
        """
        INSERT INTO nowave.reports (
            id,
            author_id,
            client_report_id,
            category,
            positioning_mode,
            final_position,
            observed_at,
            created_at,
            expires_at,
            status,
            updated_at
        )
        VALUES (
            %s, %s, %s, 'obstruction', 'manual',
            'SRID=4326;POINT(5 43)',
            %s, %s, %s, 'active', %s
        )
        """,
        (
            report_id,
            author_id,
            uuid4(),
            observed_at,
            observed_at,
            observed_at + timedelta(hours=24),
            observed_at,
        ),
    )

    return report_id


def remove_report(connection, report_id):
    now = datetime.now(UTC)

    connection.execute(
        """
        UPDATE nowave.reports
        SET status = 'removed', removed_at = %s, updated_at = %s
        WHERE id = %s
        """,
        (now, now, report_id),
    )


def test_list_reports_uses_effective_status(
    db,
    dsn,
    monkeypatch,
):
    connection, ids = db
    expired_id = insert_expired_active_report(
        connection,
        ids["user"],
    )
    remove_report(connection, ids["manual"])
    connection.commit()

    repository = repository_for_test(dsn, monkeypatch)
    now = datetime.now(UTC)

    def statuses(status):
        reports = read_all(
            lambda page: repository.list_reports(
                page=page,
                limit=100,
                status=status,
                now=now,
            )
        )

        return {report.id: report for report in reports}

    every_report = statuses(None)
    active = statuses(ReportStatus.ACTIVE)
    expired = statuses(ReportStatus.EXPIRED)
    removed = statuses(ReportStatus.REMOVED)

    assert every_report[expired_id].status == ReportStatus.EXPIRED
    assert expired_id in expired
    assert expired_id not in active

    assert ids["manual"] in removed
    assert removed[ids["manual"]].removed_at is not None
    assert ids["manual"] not in active

    assert ids["report"] in active
    assert every_report[ids["report"]].photo_status == (
        UploadStatus.PENDING
    )
    assert every_report[ids["report"]].author_username == (
        str(ids["user"])
    )
    assert every_report[ids["manual"]].photo_status is None

    assert all(
        report.status == ReportStatus.ACTIVE
        and report.expires_at > now
        for report in active.values()
    )


def test_list_reports_paginates_newest_first(
    db,
    dsn,
    monkeypatch,
):
    connection, ids = db
    insert_expired_active_report(connection, ids["user"])
    connection.commit()

    repository = repository_for_test(dsn, monkeypatch)
    now = datetime.now(UTC)

    first = repository.list_reports(
        page=1,
        limit=1,
        status=None,
        now=now,
    )
    second = repository.list_reports(
        page=2,
        limit=1,
        status=None,
        now=now,
    )

    assert first.total >= 3
    assert first.pages == first.total
    assert second.total == first.total
    assert len(first.items) == 1
    assert len(second.items) == 1
    assert first.items[0].id != second.items[0].id
    assert (
        first.items[0].observed_at
        >= second.items[0].observed_at
    )

    beyond = repository.list_reports(
        page=first.pages + 1,
        limit=1,
        status=None,
        now=now,
    )

    assert beyond.items == []
    assert beyond.total == first.total


def test_get_report_reads_removed_report_for_moderation(
    db,
    dsn,
    monkeypatch,
):
    connection, ids = db
    remove_report(connection, ids["report"])
    connection.execute(
        """
        UPDATE nowave.boats
        SET name = 'Sea Explorer'
        WHERE id = %s
        """,
        (ids["boat"],),
    )
    connection.commit()

    repository = repository_for_test(dsn, monkeypatch)

    report = repository.get_report(
        report_id=ids["report"],
        now=datetime.now(UTC),
    )

    assert report.status == ReportStatus.REMOVED
    assert report.removed_at is not None
    assert report.author_deleted is False
    assert report.author_id == ids["user"]
    # The seeded author hides both name and boat from the public detail.
    assert report.author_username == str(ids["user"])
    assert report.author_email == f"{ids['user']}@nowave.test"
    assert report.author_status == UserStatus.ACTIVE
    assert report.boat_name == "Sea Explorer"
    assert report.boat_type is not None
    assert report.photo_status == UploadStatus.PENDING
    assert report.photo_hidden_at is None
    assert (report.longitude, report.latitude) == (5.0, 43.0)


def test_get_report_marks_expired_report(
    db,
    dsn,
    monkeypatch,
):
    connection, ids = db
    expired_id = insert_expired_active_report(
        connection,
        ids["user"],
    )
    connection.commit()

    repository = repository_for_test(dsn, monkeypatch)

    report = repository.get_report(
        report_id=expired_id,
        now=datetime.now(UTC),
    )

    assert report.status == ReportStatus.EXPIRED
    assert report.photo_status is None


def test_get_report_with_deleted_author(
    db,
    dsn,
    monkeypatch,
):
    connection, ids = db
    connection.execute(
        "DELETE FROM nowave.users WHERE id = %s",
        (ids["user"],),
    )
    connection.commit()

    repository = repository_for_test(dsn, monkeypatch)

    report = repository.get_report(
        report_id=ids["manual"],
        now=datetime.now(UTC),
    )

    assert report.author_deleted is True
    assert report.author_id is None
    assert report.author_username is None
    assert report.author_email is None
    assert report.author_status is None
    assert report.boat_type is None


def test_get_missing_report_returns_none(dsn, monkeypatch):
    repository = repository_for_test(dsn, monkeypatch)

    assert repository.get_report(
        report_id=uuid4(),
        now=datetime.now(UTC),
    ) is None


def test_list_users_filters_status_and_counts_reports(
    db,
    dsn,
    monkeypatch,
):
    connection, ids = db
    connection.execute(
        """
        UPDATE nowave.users
        SET status = 'suspended'
        WHERE id = %s
        """,
        (ids["user"],),
    )
    connection.commit()

    repository = repository_for_test(dsn, monkeypatch)

    def users(status):
        result = read_all(
            lambda page: repository.list_users(
                page=page,
                limit=100,
                status=status,
            )
        )

        return {user.id: user for user in result}

    every_user = users(None)
    suspended = users(UserStatus.SUSPENDED)
    active = users(UserStatus.ACTIVE)

    assert ids["user"] in suspended
    assert ids["user"] not in active
    assert ids["admin"] in active

    user = every_user[ids["user"]]

    assert user.email == f"{ids['user']}@nowave.test"
    assert user.role == UserRole.USER
    assert user.status == UserStatus.SUSPENDED
    assert user.reports_count == 2
    assert every_user[ids["admin"]].reports_count == 0
    assert every_user[ids["admin"]].role == UserRole.ADMIN


def test_list_moderation_actions_keeps_orphan_entries(
    db,
    dsn,
    monkeypatch,
):
    connection, ids = db
    repository = repository_for_test(dsn, monkeypatch)

    def actions():
        result = read_all(
            lambda page: repository.list_moderation_actions(
                page=page,
                limit=100,
            )
        )

        return {action.id: action for action in result}

    action = actions()[ids["audit"]]

    assert action.action == ModerationActionType.REMOVE_REPORT
    assert action.admin_user_id == ids["admin"]
    assert action.admin_username == str(ids["admin"])
    assert action.target_report_id == ids["report"]
    assert action.reason == "Reported obstruction verified"

    connection.execute(
        "DELETE FROM nowave.users WHERE id = %s",
        (ids["admin"],),
    )
    connection.commit()

    orphan = actions()[ids["audit"]]

    assert orphan.admin_user_id is None
    assert orphan.admin_username is None
    assert orphan.target_report_id == ids["report"]
    assert orphan.reason == action.reason


def test_admin_reads_work_with_runtime_role(
    db,
    dsn,
    monkeypatch,
):
    _, ids = db

    role_name = "nw120_runtime_" + uuid4().hex
    role = sql.Identifier(role_name)

    with psycopg.connect(
        dsn,
        autocommit=True,
    ) as admin:
        admin.execute(
            sql.SQL(
                "CREATE ROLE {} "
                "NOSUPERUSER NOCREATEDB NOCREATEROLE"
            ).format(role)
        )

        try:
            grant_runtime_table_permissions(
                admin,
                role_name,
            )

            repository = repository_for_test(
                make_conninfo(
                    dsn,
                    options=f"-c role={role_name}",
                ),
                monkeypatch,
            )
            now = datetime.now(UTC)

            assert repository.list_reports(
                page=1,
                limit=1,
                status=ReportStatus.ACTIVE,
                now=now,
            ).total >= 1
            assert repository.get_report(
                report_id=ids["report"],
                now=now,
            ) is not None
            assert repository.list_users(
                page=1,
                limit=1,
                status=None,
            ).total >= 2
            assert repository.list_moderation_actions(
                page=1,
                limit=1,
            ).total >= 1
        finally:
            admin.execute(
                sql.SQL("DROP OWNED BY {}").format(role)
            )
            admin.execute(
                sql.SQL("DROP ROLE {}").format(role)
            )
