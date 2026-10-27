from datetime import UTC, datetime, timedelta
from uuid import uuid4

from fastapi.testclient import TestClient
import psycopg

from app.domain.report import Report, ReportCategory
from app.domain.user import User
from app.infrastructure.repositories.postgresql_report_repository import PostgreSQLReportRepository
from app.infrastructure.repositories.postgresql_user_repository import PostgreSQLUserRepository
from app.main import app


def test_public_api_filters_liveness_privacy_dateline_and_pagination(dsn, monkeypatch):
    monkeypatch.setenv("DATABASE_URL", dsn)
    unique = uuid4().hex
    user = User(firebase_uid=unique, username=f"private-{unique}", email=f"{unique}@nowave.test")
    PostgreSQLUserRepository().save(user)
    reports = []
    now = datetime.now(UTC)
    for index, longitude in enumerate((175, -175, 0, 176, 177, 178)):
        # Create the historical fixture at its original time; dates are immutable.
        created_at = now - timedelta(hours=25) if index == 4 else now
        with monkeypatch.context() as clock:
            clock.setattr("app.domain.report.utc_now", lambda: created_at)
            report = Report.create_manual(
                author_id=user.id, client_report_id=uuid4(), category=ReportCategory.POLLUTION,
                longitude=longitude, latitude=-15, description=unique,
                observed_at=created_at - timedelta(minutes=5),
            )
        PostgreSQLReportRepository().save(report)
        reports.append(report)
    with psycopg.connect(dsn) as connection:
        connection.execute("UPDATE nowave.reports SET status = 'removed', removed_at = now() WHERE id = %s", (reports[3].id,))
        connection.execute("UPDATE nowave.reports SET status = 'expired' WHERE id = %s", (reports[5].id,))

    # Time-expired but still status='active': do not depend on a cleanup job.
    with psycopg.connect(dsn) as connection:
        expired = connection.execute(
            "SELECT status, observed_at, expires_at FROM nowave.reports WHERE id = %s",
            (reports[4].id,),
        ).fetchone()
    assert expired[0] == "active"
    assert expired[1] == reports[4].observed_at
    assert expired[2] == expired[1] + timedelta(hours=24)
    assert expired[2] < now

    client = TestClient(app)
    params = {"west": 170, "east": -170, "south": -20, "north": -10, "q": unique, "limit": 1}
    first = client.get("/api/v1/map/observations", params=params)
    assert first.status_code == 200
    assert first.json()["has_more"] is True
    second = client.get("/api/v1/map/observations", params={**params, "cursor": first.json()["next_cursor"]})
    assert second.json()["has_more"] is False
    items = first.json()["items"] + second.json()["items"]
    assert {item["id"] for item in items} == {str(report.id) for report in reports[:2]}
    assert all("author_username" not in item and "author_email" not in item for item in items)
    assert client.get("/api/v1/map/observations", params={"q": user.username}).json()["items"] == []

    with psycopg.connect(dsn) as connection:
        connection.execute("UPDATE nowave.users SET show_user_name = true WHERE id = %s", (user.id,))
    visible = client.get("/api/v1/map/observations", params={"q": user.username}).json()["items"]
    assert len(visible) == 3
    assert all(item["author_username"] == user.username for item in visible)
    assert client.get("/api/v1/map/observations", params={"q": unique, "category": "obstruction"}).json()["items"] == []
    assert client.get("/api/v1/map/observations", params={"q": "%"}).json()["items"] == []
