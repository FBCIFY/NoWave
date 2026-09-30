from datetime import UTC, datetime
from uuid import uuid4

from app.domain.report import (
    ReportPositioningMode,
    ReportStatus,
)
from app.infrastructure.repositories.postgresql_report_detail_repository import (
    PostgreSQLReportDetailRepository,
)


def repository_for_test(
    dsn,
    monkeypatch,
):
    monkeypatch.setenv(
        "DATABASE_URL",
        dsn,
    )

    return PostgreSQLReportDetailRepository()


def test_reads_manual_report(
    db,
    dsn,
    monkeypatch,
):
    _, ids = db

    repository = repository_for_test(
        dsn,
        monkeypatch,
    )

    report = repository.get_by_id(
        ids["manual"]
    )

    assert report is not None
    assert report.id == ids["manual"]

    assert (
        report.positioning_mode
        == ReportPositioningMode.MANUAL
    )

    assert report.status == ReportStatus.ACTIVE

    assert report.longitude == 5.0
    assert report.latitude == 43.0

    assert report.photo_status is None
    assert report.photo_object_key is None
    assert report.photo_hidden_at is None


def test_hidden_author_and_boat_are_not_exposed(
    db,
    dsn,
    monkeypatch,
):
    _, ids = db

    repository = repository_for_test(
        dsn,
        monkeypatch,
    )

    report = repository.get_by_id(
        ids["report"]
    )

    assert report is not None

    assert report.author_deleted is False
    assert report.author_username is None

    assert report.boat_name is None
    assert report.boat_type is None

    assert report.photo_status == "pending"


def test_visible_author_and_boat_are_loaded(
    db,
    dsn,
    monkeypatch,
):
    connection, ids = db

    connection.execute(
        """
        UPDATE blueway.users
        SET
            username = %s,
            show_user_name = TRUE,
            show_boat_info = TRUE
        WHERE id = %s
        """,
        (
            "Jonathan",
            ids["user"],
        ),
    )

    connection.execute(
        """
        UPDATE blueway.boats
        SET name = %s
        WHERE id = %s
        """,
        (
            "Asteria",
            ids["boat"],
        ),
    )

    connection.commit()

    repository = repository_for_test(
        dsn,
        monkeypatch,
    )

    report = repository.get_by_id(
        ids["report"]
    )

    assert report is not None

    assert report.author_deleted is False
    assert report.author_username == "Jonathan"

    assert report.boat_name == "Asteria"
    assert report.boat_type == "voilier"


def test_deleted_author_is_detected(
    db,
    dsn,
    monkeypatch,
):
    connection, ids = db

    connection.execute(
        """
        DELETE FROM blueway.users
        WHERE id = %s
        """,
        (ids["user"],),
    )

    connection.commit()

    repository = repository_for_test(
        dsn,
        monkeypatch,
    )

    report = repository.get_by_id(
        ids["report"]
    )

    assert report is not None

    assert report.author_deleted is True
    assert report.author_username is None

    assert report.boat_name is None
    assert report.boat_type is None


def test_uploaded_photo_metadata_is_loaded(
    db,
    dsn,
    monkeypatch,
):
    connection, ids = db

    object_key = (
        f"reports/{uuid4()}.jpg"
    )

    hidden_at = datetime.now(UTC)

    connection.execute(
        """
        UPDATE blueway.report_photos
        SET
            upload_status = 'uploaded',
            object_key = %s,
            size_bytes = 1000,
            mime_type = 'image/jpeg',
            uploaded_at = NOW(),
            hidden_at = %s,
            updated_at = NOW()
        WHERE report_id = %s
        """,
        (
            object_key,
            hidden_at,
            ids["report"],
        ),
    )

    connection.commit()

    repository = repository_for_test(
        dsn,
        monkeypatch,
    )

    report = repository.get_by_id(
        ids["report"]
    )

    assert report is not None

    assert report.photo_status == "uploaded"
    assert report.photo_object_key == object_key
    assert report.photo_hidden_at is not None


def test_unknown_report_returns_none(
    dsn,
    monkeypatch,
):
    repository = repository_for_test(
        dsn,
        monkeypatch,
    )

    assert (
        repository.get_by_id(uuid4())
        is None
    )
