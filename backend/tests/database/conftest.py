import os
from pathlib import Path
import subprocess
import sys
import uuid

from alembic import command
from alembic.config import Config
import psycopg
from psycopg import sql
from psycopg.conninfo import conninfo_to_dict, make_conninfo
import pytest
from sqlalchemy import create_engine
from sqlalchemy.engine import URL
from sqlalchemy.pool import NullPool

ROOT = Path(__file__).resolve().parents[3]
ALEMBIC_INI = ROOT / 'backend/alembic.ini'


def sqlalchemy_url(dsn):
    params = conninfo_to_dict(dsn)
    return URL.create(
        'postgresql+psycopg',
        username=params.get('user'),
        password=params.get('password'),
        host=params.get('host'),
        port=int(params['port']) if params.get('port') else None,
        database=params.get('dbname'),
    )


def run_alembic(dsn, operation, revision):
    config = Config(str(ALEMBIC_INI))
    engine = create_engine(sqlalchemy_url(dsn), poolclass=NullPool)
    try:
        with engine.connect() as connection:
            config.attributes['connection'] = connection
            operation(config, revision)
    finally:
        engine.dispose()


def upgrade_database(dsn, revision='head'):
    run_alembic(dsn, command.upgrade, revision)


def downgrade_database(dsn, revision='base'):
    run_alembic(dsn, command.downgrade, revision)


def upgrade_database_cli(dsn):
    env = os.environ.copy()
    env['DATABASE_URL'] = sqlalchemy_url(dsn).render_as_string(hide_password=False)
    subprocess.run(
        [sys.executable, '-m', 'alembic', '-c', str(ALEMBIC_INI), 'upgrade', 'head'],
        cwd=ROOT / 'backend',
        env=env,
        check=True,
        capture_output=True,
        text=True,
    )


@pytest.fixture(scope='session')
def dsn():
    """Never reset an existing database. Create and drop our own random database."""
    admin_dsn = os.environ['BLUEWAY_TEST_ADMIN_URL']
    name = 'blueway_test_' + uuid.uuid4().hex
    params = conninfo_to_dict(admin_dsn)
    params['dbname'] = name
    test_dsn = make_conninfo(**params)
    with psycopg.connect(admin_dsn, autocommit=True) as admin:
        admin.execute(sql.SQL('CREATE DATABASE {}').format(sql.Identifier(name)))
    try:
        upgrade_database(test_dsn)
        yield test_dsn
    finally:
        with psycopg.connect(admin_dsn, autocommit=True) as admin:
            admin.execute(sql.SQL('DROP DATABASE {} WITH (FORCE)').format(sql.Identifier(name)))


def insert(conn, table, **values):
    query = sql.SQL('INSERT INTO nowave.{} ({}) VALUES ({}) RETURNING *').format(
        sql.Identifier(table), sql.SQL(',').join(map(sql.Identifier, values)),
        sql.SQL(',').join(sql.Placeholder() for _ in values))
    return conn.execute(query, list(values.values())).fetchone()


def seed(conn):
    from datetime import datetime, timezone, timedelta
    now = datetime.now(timezone.utc)
    ids = {x: uuid.uuid4() for x in ['user', 'admin', 'boat', 'device', 'report', 'manual', 'notification', 'history', 'audit']}
    for user, role in [('user','user'), ('admin','admin')]:
        insert(
            conn,
            'users',
            id=ids[user],
            firebase_uid=str(ids[user]),
            username=str(ids[user]),
            email=f'{ids[user]}@blueway.test',
            role=role,
            status='active',
            created_at=now,
            updated_at=now,
        )
    insert(conn, 'boats', id=ids['boat'], user_id=ids['user'], boat_type='voilier', created_at=now, updated_at=now)
    insert(conn, 'devices', id=ids['device'], user_id=ids['user'], installation_id=uuid.uuid4(),
           platform='ios', is_active=True, last_seen_at=now)
    point = 'SRID=4326;POINT(5 43)'
    insert(conn, 'device_positions', device_id=ids['device'], position=point, accuracy_m=50,
           measured_at=now, received_at=now)
    for report, mode in [('report','photo'), ('manual','manual')]:
        insert(conn, 'reports', id=ids[report], author_id=ids['user'], client_report_id=uuid.uuid4(),
               category='pollution', positioning_mode=mode, final_position=point, observed_at=now,
               created_at=now, expires_at=now+timedelta(hours=24), status='active', updated_at=now)
    insert(conn, 'report_positioning', report_id=ids['report'], observer_position=point, gps_accuracy_m=0,
           azimuth_deg=0, inclination_deg=-10, camera_height_m=2, captured_at=now)
    insert(conn, 'report_photos', report_id=ids['report'], upload_status='pending', created_at=now, updated_at=now)
    insert(conn, 'notifications', id=ids['notification'], report_id=ids['report'], device_id=ids['device'],
           report_version=1, status='pending', next_attempt_at=now, created_at=now, updated_at=now)
    insert(conn, 'alert_history', id=ids['history'], user_id=ids['user'], report_id=ids['report'],
           report_version=1, category='pollution', position=point, distance_m=18520, alerted_at=now)
    insert(conn, 'moderation_actions', id=ids['audit'], admin_user_id=ids['admin'], target_report_id=ids['report'],
           action='remove_report', reason='Reported obstruction verified', created_at=now)
    return ids


@pytest.fixture
def db(dsn):
    with psycopg.connect(dsn) as conn:
        ids = seed(conn)
        conn.commit()
        try:
            yield conn, ids
        finally:
            conn.rollback()
