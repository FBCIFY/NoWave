from concurrent.futures import ThreadPoolExecutor
from contextlib import contextmanager
from datetime import UTC, datetime, timedelta
from threading import Barrier, Event
from time import sleep
from uuid import uuid4

import psycopg
from psycopg import sql
from psycopg.conninfo import make_conninfo
import pytest

from app.domain.report import Report, ReportCategory
from app.infrastructure.database.runtime_permissions import grant_runtime_table_permissions
from app.infrastructure.repositories import postgresql_map_tile_repository as tiles
from app.infrastructure.cache.map_tile_cache import MapTileCache
from app.infrastructure.repositories.postgresql_report_repository import PostgreSQLReportRepository


@pytest.fixture
def cached_tiles(db, dsn, monkeypatch):
    monkeypatch.setenv("DATABASE_URL", dsn)
    monkeypatch.setattr(tiles, "tile_cache", MapTileCache())
    builds = []
    original = tiles.database_connection

    @contextmanager
    def counted_connection(*args, **kwargs):
        with original(*args, **kwargs) as connection:
            class Connection:
                def execute(self, query, params=None):
                    if "ST_AsMVT(" in query:
                        builds.append(query)
                    return connection.execute(query, params)
            yield Connection()

    monkeypatch.setattr(tiles, "database_connection", counted_connection)
    report = Report.create_manual(
        author_id=db[1]["user"], client_report_id=uuid4(),
        category=ReportCategory.POLLUTION, longitude=5, latitude=43,
        observed_at=datetime.now(UTC) - timedelta(minutes=1),
    )
    args = dict(zoom=0, x=0, y=0, report_id=report.id)
    return tiles.PostgreSQLMapTileRepository(), report, args, builds


def test_cached_empty_tile_creation_removal_restore_and_rollback(cached_tiles, dsn):
    repository, report, args, builds = cached_tiles
    assert repository.get_tile(**args) == b""
    assert repository.get_tile(**args) == b""
    assert len(builds) == 1
    PostgreSQLReportRepository().save(report)
    content = repository.get_tile(**args)
    assert content
    assert repository.get_tile(**args) == content
    assert len(builds) == 2
    with psycopg.connect(dsn) as connection:
        connection.execute(
            "UPDATE nowave.reports SET status='removed', removed_at=now() WHERE id=%s",
            (report.id,),
        )
        connection.rollback()
    assert repository.get_tile(**args) == content
    assert len(builds) == 2
    with psycopg.connect(dsn) as connection:
        connection.execute(
            "UPDATE nowave.reports SET status='removed', removed_at=now() WHERE id=%s",
            (report.id,),
        )
    assert repository.get_tile(**args) == b""
    with psycopg.connect(dsn) as connection:
        connection.execute(
            "UPDATE nowave.reports SET status='active', removed_at=NULL WHERE id=%s",
            (report.id,),
        )
    assert repository.get_tile(**args) == content
    assert len(builds) == 4


def test_concurrent_identical_tiles_only_build_once(cached_tiles):
    repository, report, args, builds = cached_tiles
    PostgreSQLReportRepository().save(report)
    start = Barrier(8)

    def request():
        start.wait(timeout=5)
        return repository.get_tile(**args)

    with ThreadPoolExecutor(max_workers=8) as pool:
        results = list(pool.map(lambda _: request(), range(8)))
    assert results[0] and all(value == results[0] for value in results)
    assert len(builds) == 1


def test_cached_tile_expires_without_any_database_write(cached_tiles, dsn):
    repository, report, args, builds = cached_tiles
    # Insert a report with one second of lifetime left. No write follows it.
    with psycopg.connect(dsn) as connection:
        connection.execute(
            """INSERT INTO nowave.reports
            (id, author_id, client_report_id, category, positioning_mode,
             final_position, observed_at, created_at, expires_at, status, updated_at)
            VALUES (%s, %s, %s, 'pollution', 'manual', 'SRID=4326;POINT(5 43)',
                    now()-interval '24 hours'+interval '1 second', now(),
                    now()+interval '1 second', 'active', now())""",
            (report.id, report.author_id, report.client_report_id),
        )
    assert repository.get_tile(**args)
    sleep(1.05)
    assert repository.get_tile(**args) == b""
    assert len(builds) == 2


def test_write_during_build_cannot_label_old_tile_with_new_revision(cached_tiles, dsn, monkeypatch):
    repository, report, args, builds = cached_tiles
    PostgreSQLReportRepository().save(report)
    entered, release = Event(), Event()
    original = tiles.database_connection

    @contextmanager
    def paused_connection(*a, **kw):
        with original(*a, **kw) as connection:
            class Connection:
                def execute(self, query, params=None):
                    if "ST_AsMVT(" in query:
                        entered.set()
                        assert release.wait(5)
                    return connection.execute(query, params)
            yield Connection()

    monkeypatch.setattr(tiles, "database_connection", paused_connection)
    with ThreadPoolExecutor(max_workers=1) as pool:
        pending = pool.submit(repository.get_tile, **args)
        try:
            assert entered.wait(5)
            with psycopg.connect(dsn) as connection:
                connection.execute(
                    "UPDATE nowave.reports SET status='removed', removed_at=now() WHERE id=%s",
                    (report.id,),
                )
        finally:
            release.set()
        assert pending.result(timeout=5)
    assert repository.get_tile(**args) == b""
    assert len(builds) == 2


def test_runtime_role_can_read_cache_and_invalidate_without_editing_revision(cached_tiles, dsn, monkeypatch):
    repository, report, args, builds = cached_tiles
    name = "tile_runtime_" + uuid4().hex
    role = sql.Identifier(name)
    with psycopg.connect(dsn, autocommit=True) as admin:
        admin.execute(sql.SQL("CREATE ROLE {} NOSUPERUSER").format(role))
        try:
            grant_runtime_table_permissions(admin, name)
            monkeypatch.setenv("DATABASE_URL", make_conninfo(dsn, options=f"-c role={name}"))
            assert repository.get_tile(**args) == b""
            PostgreSQLReportRepository().save(report)
            assert repository.get_tile(**args)
            assert not admin.execute(
                "SELECT has_table_privilege(%s, 'nowave.map_cache_revision', 'UPDATE')",
                (name,),
            ).fetchone()[0]
        finally:
            admin.execute(sql.SQL("DROP OWNED BY {}").format(role))
            admin.execute(sql.SQL("DROP ROLE {}").format(role))
