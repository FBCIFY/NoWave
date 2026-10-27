import base64
from contextlib import contextmanager
from datetime import UTC, datetime, timedelta
from uuid import UUID

import pytest

from app.application.ports.public_observation_reader import ObservationQuery
from app.application.services.list_public_observations import decode_observation_cursor
from app.domain.report import ReportCategory
from app.infrastructure.repositories.postgresql_public_observation_repository import PostgreSQLPublicObservationRepository


@pytest.mark.parametrize("payload", [
    "2026-10-26T12:00:00|00000000-0000-0000-0000-000000000001",
    "2026-10-26T12:00:00+00:00|not-a-uuid", "not-a-date|1",
    "9999-12-31T23:59:59-23:59|00000000-0000-0000-0000-000000000001",
])
def test_invalid_cursor_payloads_are_rejected(payload):
    cursor = base64.urlsafe_b64encode(payload.encode()).decode()
    with pytest.raises(ValueError, match="Invalid observation cursor"):
        decode_observation_cursor(cursor)


def test_repository_queries_only_active_consented_fields_with_parameterized_filters(monkeypatch):
    calls = []
    now = datetime.now(UTC)
    row = (UUID(int=1), "pollution", 175, -10, now, now + timedelta(hours=24), "Plastique", None)

    class Cursor:
        def __enter__(self):
            return self

        def __exit__(self, *_):
            pass

        def execute(self, statement, values):
            calls.append((statement, values))

        def fetchall(self):
            return [row]

    class Connection:
        def cursor(self):
            return Cursor()

    @contextmanager
    def connection():
        yield Connection()

    monkeypatch.setattr(
        "app.infrastructure.repositories.postgresql_public_observation_repository.database_connection", connection,
    )
    query = ObservationQuery(west=170, east=-170, south=-20, north=10,
                             q="50%_\\'", category=ReportCategory.POLLUTION, limit=5,
                             after=(now, UUID(int=2)))
    result = PostgreSQLPublicObservationRepository().list_active(query)
    sql, values = calls[0]
    assert "r.status = 'active'" in sql
    assert "r.expires_at > statement_timestamp()" in sql
    assert "r.removed_at IS NULL" in sql
    assert "CASE WHEN u.show_user_name = TRUE" in sql
    assert "u.show_user_name = TRUE AND u.username ILIKE %s" in sql
    assert "50%" not in sql
    assert values[:8] == [170, -20, 180, 10, -180, -20, -170, 10]
    assert values[8:] == ["pollution", "%50\\%\\_\\\\'%", "%50\\%\\_\\\\'%", now, UUID(int=2), 6]
    assert result[0].id == row[0]
    assert result[0].author_username is None
