from datetime import UTC, datetime, timedelta
from uuid import uuid4

import psycopg
from psycopg import sql
from psycopg.conninfo import make_conninfo
import pytest

from app.domain.errors import (
    AdminRequiredError,
    ModerationConflictError,
    PhotoNotFoundError,
    ReportNotFoundError,
    UserNotFoundError,
)
from app.domain.report_photo import UploadStatus
from app.domain.user import UserStatus
from app.infrastructure.database.runtime_permissions import (
    grant_runtime_table_permissions,
)
from app.infrastructure.repositories.postgresql_moderation_repository import (
    PostgreSQLModerationRepository,
)


def repository_for_test(
    dsn,
    monkeypatch,
):
    monkeypatch.setenv(
        "DATABASE_URL",
        dsn,
    )

    return PostgreSQLModerationRepository()


def report_state(connection, report_id):
    return connection.execute(
        """
        SELECT status, removed_at, expires_at, version
        FROM nowave.reports
        WHERE id = %s
        """,
        (report_id,),
    ).fetchone()


def audit_rows(connection, column, target_id):
    return connection.execute(
        sql.SQL(
            """
            SELECT
                admin_user_id,
                action,
                reason,
                previous_status,
                new_status
            FROM nowave.moderation_actions
            WHERE {} = %s
            ORDER BY created_at
            """
        ).format(sql.Identifier(column)),
        (target_id,),
    ).fetchall()


def upload_seed_photo(connection, ids):
    now = datetime.now(UTC)

    connection.execute(
        """
        UPDATE nowave.report_photos
        SET
            upload_status = 'uploaded',
            object_key = %s,
            size_bytes = 1200,
            mime_type = 'image/jpeg',
            uploaded_at = %s,
            updated_at = %s
        WHERE report_id = %s
        """,
        (
            f"reports/{ids['report']}.jpg",
            now,
            now,
            ids["report"],
        ),
    )
    connection.commit()


def test_remove_report_writes_audit(
    db,
    dsn,
    monkeypatch,
):
    connection, ids = db
    repository = repository_for_test(dsn, monkeypatch)
    _, _, expires_at, version = report_state(
        connection,
        ids["manual"],
    )
    connection.commit()

    repository.remove_report(
        report_id=ids["manual"],
        admin_user_id=ids["admin"],
        reason="Faux signalement confirmé",
        now=datetime.now(UTC),
    )

    status, removed_at, new_expires_at, new_version = (
        report_state(connection, ids["manual"])
    )

    assert status == "removed"
    assert removed_at is not None
    assert new_expires_at == expires_at
    assert new_version == version

    assert audit_rows(
        connection,
        "target_report_id",
        ids["manual"],
    ) == [
        (
            ids["admin"],
            "remove_report",
            "Faux signalement confirmé",
            "active",
            "removed",
        )
    ]


def test_restore_report_keeps_expiration(
    db,
    dsn,
    monkeypatch,
):
    connection, ids = db
    repository = repository_for_test(dsn, monkeypatch)
    _, _, expires_at, version = report_state(
        connection,
        ids["manual"],
    )
    connection.commit()

    repository.remove_report(
        report_id=ids["manual"],
        admin_user_id=ids["admin"],
        reason="Faux signalement",
        now=datetime.now(UTC),
    )
    repository.restore_report(
        report_id=ids["manual"],
        admin_user_id=ids["admin"],
        reason="Signalement vérifié",
        now=datetime.now(UTC),
    )

    assert report_state(connection, ids["manual"]) == (
        "active",
        None,
        expires_at,
        version,
    )
    assert [
        row[1]
        for row in audit_rows(
            connection,
            "target_report_id",
            ids["manual"],
        )
    ] == ["remove_report", "restore_report"]


def test_restore_after_expiration_marks_report_expired(
    db,
    dsn,
    monkeypatch,
):
    connection, ids = db
    repository = repository_for_test(dsn, monkeypatch)
    observed_at = datetime.now(UTC) - timedelta(hours=25)
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
            updated_at,
            removed_at
        )
        VALUES (
            %s, %s, %s, 'pollution', 'manual',
            'SRID=4326;POINT(5 43)',
            %s, %s, %s, 'removed', %s, %s
        )
        """,
        (
            report_id,
            ids["user"],
            uuid4(),
            observed_at,
            observed_at,
            observed_at + timedelta(hours=24),
            observed_at,
            observed_at,
        ),
    )
    connection.commit()

    repository.restore_report(
        report_id=report_id,
        admin_user_id=ids["admin"],
        reason="Signalement vérifié",
        now=datetime.now(UTC),
    )

    status, removed_at, expires_at, _ = report_state(
        connection,
        report_id,
    )

    assert status == "expired"
    assert removed_at is None
    assert expires_at == observed_at + timedelta(hours=24)


def test_conflict_rolls_back_without_audit(
    db,
    dsn,
    monkeypatch,
):
    connection, ids = db
    repository = repository_for_test(dsn, monkeypatch)
    connection.commit()

    with pytest.raises(ModerationConflictError):
        repository.restore_report(
            report_id=ids["manual"],
            admin_user_id=ids["admin"],
            reason="Signalement vérifié",
            now=datetime.now(UTC),
        )

    assert report_state(connection, ids["manual"])[0] == (
        "active"
    )
    assert audit_rows(
        connection,
        "target_report_id",
        ids["manual"],
    ) == []


def test_inactive_admin_rolls_back_change(
    db,
    dsn,
    monkeypatch,
):
    connection, ids = db
    repository = repository_for_test(dsn, monkeypatch)

    connection.execute(
        """
        UPDATE nowave.users
        SET status = 'suspended'
        WHERE id = %s
        """,
        (ids["admin"],),
    )
    connection.commit()

    with pytest.raises(AdminRequiredError):
        repository.remove_report(
            report_id=ids["manual"],
            admin_user_id=ids["admin"],
            reason="Faux signalement",
            now=datetime.now(UTC),
        )

    assert report_state(connection, ids["manual"])[:2] == (
        "active",
        None,
    )
    assert audit_rows(
        connection,
        "target_report_id",
        ids["manual"],
    ) == []


def test_non_admin_cannot_write_audit(
    db,
    dsn,
    monkeypatch,
):
    connection, ids = db
    repository = repository_for_test(dsn, monkeypatch)
    connection.commit()

    with pytest.raises(AdminRequiredError):
        repository.suspend_user(
            user_id=ids["admin"],
            admin_user_id=ids["user"],
            reason="Abus",
            now=datetime.now(UTC),
        )

    assert connection.execute(
        "SELECT status FROM nowave.users WHERE id = %s",
        (ids["admin"],),
    ).fetchone()[0] == "active"


def test_missing_report_raises_not_found(
    db,
    dsn,
    monkeypatch,
):
    repository = repository_for_test(dsn, monkeypatch)
    _, ids = db

    with pytest.raises(ReportNotFoundError):
        repository.remove_report(
            report_id=uuid4(),
            admin_user_id=ids["admin"],
            reason="Faux signalement",
            now=datetime.now(UTC),
        )

    with pytest.raises(ReportNotFoundError):
        repository.hide_photo(
            report_id=uuid4(),
            admin_user_id=ids["admin"],
            reason="Photo inappropriée",
            now=datetime.now(UTC),
        )


def test_hide_photo_keeps_upload_status(
    db,
    dsn,
    monkeypatch,
):
    connection, ids = db
    repository = repository_for_test(dsn, monkeypatch)
    upload_seed_photo(connection, ids)
    now = datetime.now(UTC)

    photo = repository.hide_photo(
        report_id=ids["report"],
        admin_user_id=ids["admin"],
        reason="Photo inappropriée",
        now=now,
    )

    assert photo.report_id == ids["report"]
    assert photo.upload_status == UploadStatus.UPLOADED
    assert photo.size_bytes == 1200
    assert photo.hidden_at == now

    assert connection.execute(
        """
        SELECT upload_status, hidden_at IS NOT NULL
        FROM nowave.report_photos
        WHERE report_id = %s
        """,
        (ids["report"],),
    ).fetchone() == ("uploaded", True)

    assert audit_rows(
        connection,
        "target_photo_report_id",
        ids["report"],
    ) == [
        (
            ids["admin"],
            "hide_photo",
            "Photo inappropriée",
            None,
            None,
        )
    ]

    with pytest.raises(ModerationConflictError):
        repository.hide_photo(
            report_id=ids["report"],
            admin_user_id=ids["admin"],
            reason="Photo inappropriée",
            now=now,
        )


def test_hide_photo_rejects_pending_and_missing_photo(
    db,
    dsn,
    monkeypatch,
):
    connection, ids = db
    repository = repository_for_test(dsn, monkeypatch)
    connection.commit()

    with pytest.raises(ModerationConflictError):
        repository.hide_photo(
            report_id=ids["report"],
            admin_user_id=ids["admin"],
            reason="Photo inappropriée",
            now=datetime.now(UTC),
        )

    with pytest.raises(PhotoNotFoundError):
        repository.hide_photo(
            report_id=ids["manual"],
            admin_user_id=ids["admin"],
            reason="Photo inappropriée",
            now=datetime.now(UTC),
        )

    assert audit_rows(
        connection,
        "target_photo_report_id",
        ids["report"],
    ) == []


def test_suspend_and_reactivate_user_keep_reports(
    db,
    dsn,
    monkeypatch,
):
    connection, ids = db
    repository = repository_for_test(dsn, monkeypatch)
    connection.commit()

    suspended = repository.suspend_user(
        user_id=ids["user"],
        admin_user_id=ids["admin"],
        reason="Signalements abusifs",
        now=datetime.now(UTC),
    )

    assert suspended.id == ids["user"]
    assert suspended.status == UserStatus.SUSPENDED

    assert connection.execute(
        """
        SELECT count(*)
        FROM nowave.reports
        WHERE author_id = %s AND status = 'active'
        """,
        (ids["user"],),
    ).fetchone()[0] == 2

    with pytest.raises(ModerationConflictError):
        repository.suspend_user(
            user_id=ids["user"],
            admin_user_id=ids["admin"],
            reason="Signalements abusifs",
            now=datetime.now(UTC),
        )

    reactivated = repository.reactivate_user(
        user_id=ids["user"],
        admin_user_id=ids["admin"],
        reason="Suspension levée",
        now=datetime.now(UTC),
    )

    assert reactivated.status == UserStatus.ACTIVE
    assert audit_rows(
        connection,
        "target_user_id",
        ids["user"],
    ) == [
        (
            ids["admin"],
            "suspend_user",
            "Signalements abusifs",
            "active",
            "suspended",
        ),
        (
            ids["admin"],
            "reactivate_user",
            "Suspension levée",
            "suspended",
            "active",
        ),
    ]


def test_missing_user_raises_not_found(
    db,
    dsn,
    monkeypatch,
):
    repository = repository_for_test(dsn, monkeypatch)
    _, ids = db

    with pytest.raises(UserNotFoundError):
        repository.suspend_user(
            user_id=uuid4(),
            admin_user_id=ids["admin"],
            reason="Abus",
            now=datetime.now(UTC),
        )


def test_moderation_works_with_runtime_role(
    db,
    dsn,
    monkeypatch,
):
    connection, ids = db
    upload_seed_photo(connection, ids)

    role_name = "nw119_runtime_" + uuid4().hex
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

            repository.remove_report(
                report_id=ids["manual"],
                admin_user_id=ids["admin"],
                reason="Faux signalement",
                now=now,
            )
            repository.restore_report(
                report_id=ids["manual"],
                admin_user_id=ids["admin"],
                reason="Signalement vérifié",
                now=now,
            )
            repository.hide_photo(
                report_id=ids["report"],
                admin_user_id=ids["admin"],
                reason="Photo inappropriée",
                now=now,
            )
            repository.suspend_user(
                user_id=ids["user"],
                admin_user_id=ids["admin"],
                reason="Abus",
                now=now,
            )
            repository.reactivate_user(
                user_id=ids["user"],
                admin_user_id=ids["admin"],
                reason="Suspension levée",
                now=now,
            )
        finally:
            admin.execute(
                sql.SQL("DROP OWNED BY {}").format(role)
            )
            admin.execute(
                sql.SQL("DROP ROLE {}").format(role)
            )
