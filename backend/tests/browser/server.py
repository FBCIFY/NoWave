"""Loopback-only test server. Real app, sessions, SQL and moderation; fake identity/storage.

Never imported by production. Creates/drops a random test DB, and accepts no external DSN.
"""
import os
import json
from pathlib import Path
import re
import secrets
import subprocess
import tempfile
import tarfile
from uuid import UUID, uuid4
from datetime import UTC, datetime, timedelta

import psycopg
from psycopg import sql
from psycopg.conninfo import conninfo_to_dict, make_conninfo
import uvicorn

from tests.database.conftest import upgrade_database, insert


def main():
    params = conninfo_to_dict(os.environ['NOWAVE_TEST_ADMIN_URL'])
    if params.get('host') not in {'127.0.0.1', 'localhost'}:
        raise RuntimeError('Browser fixtures require a loopback test database')
    name = 'nowave_browser_' + uuid4().hex
    admin_dsn = make_conninfo(**params)
    params['dbname'] = name
    dsn = make_conninfo(**params)
    with psycopg.connect(admin_dsn, autocommit=True) as conn:
        conn.execute(sql.SQL('CREATE DATABASE {}').format(sql.Identifier(name)))
    try:
        upgrade_database(dsn)
        os.environ['DATABASE_URL'] = dsn
        token_config = os.getenv('NOWAVE_MAPBOX_CONFIG')
        os.environ['MAPBOX_PUBLIC_TOKEN'] = (json.loads(Path(token_config).expanduser().read_text())['MAPBOX_ACCESS_TOKEN']
                                             if token_config else 'pk.browser_fixture.token')
        os.environ.pop('DATABASE_URL_FILE', None)
        os.environ.pop('NOWAVE_ENV', None)
        now = datetime.now(UTC)
        with psycopg.connect(dsn) as conn:
            for index in range(1, 29):
                count = {2: 0, 3: 1, 4: 49, 5: 50, 6: 51, 7: 101}.get(index, 0)
                username = 'Admin Test' if index == 1 else f'User {index:02d}'
                insert(conn, 'users', id=UUID(int=index), firebase_uid=f'browser-{index}', username=username,
                       email=f'user{index}@nowave.test', role='admin' if index == 1 else 'user',
                       status='active', created_at=now, updated_at=now)
                for item in range(count):
                    id = UUID(int=index * 1000 + item)
                    insert(conn, 'reports', id=id, author_id=UUID(int=index), client_report_id=uuid4(),
                           category=['marine_animal', 'obstruction', 'pollution'][item % 3], positioning_mode='manual',
                           final_position=f'SRID=4326;POINT({-30 + item * .001} {24 + item * .001})',
                           description=f'Synthetic report {index}/{item}', observed_at=now,
                           expires_at=now + timedelta(hours=24), created_at=now, updated_at=now, status='active')
            for number, hidden in [(5020, False), (5019, True), (7040, False), (7039, False)]:
                conn.execute("UPDATE nowave.reports SET positioning_mode = 'photo' WHERE id = %s", (UUID(int=number),))
                insert(conn, 'report_positioning', report_id=UUID(int=number),
                       observer_position='SRID=4326;POINT(-30 24)', gps_accuracy_m=0, azimuth_deg=0,
                       inclination_deg=-10, camera_height_m=2, captured_at=now)
                insert(conn, 'report_photos', report_id=UUID(int=number), upload_status='uploaded',
                       object_key=f'reports/{number}.jpg', size_bytes=1200, mime_type='image/jpeg',
                       uploaded_at=now, created_at=now, updated_at=now, hidden_at=now if hidden else None)
        from app.main import app
        from app.dependencies.admin_web_session import get_admin_web_session
        from app.application.services.admin_web_session import AdminWebSession
        from app.infrastructure.repositories.postgresql_user_repository import PostgreSQLUserRepository
        from app.domain.errors import InvalidCredentialsError, InvalidSessionError
        import app.api.routes.report_details as details
        from fastapi.responses import Response

        class Identity:
            """Only provider network boundary is replaced. Active-admin checks use real SQL."""
            def __init__(self):
                self.sessions = {}

            def sign_in_with_password(self, email, password):
                if password != 'test-password' or email not in {'user1@nowave.test', 'user2@nowave.test'}:
                    raise InvalidCredentialsError()
                return email

            def verify_id_token(self, token):
                return {'uid': f"browser-{token.split('@')[0][4:]}", 'email_verified': True}

            def create_session_cookie(self, token, duration):
                cookie = secrets.token_urlsafe(32)
                self.sessions[cookie] = self.verify_id_token(token)
                return cookie

            def verify_session_cookie(self, cookie):
                if cookie not in self.sessions:
                    raise InvalidSessionError()
                return self.sessions[cookie]

        identity = Identity()
        service = AdminWebSession(web_auth_provider=identity, user_repository=PostgreSQLUserRepository())
        app.dependency_overrides[get_admin_web_session] = lambda: service

        class Storage:
            def create_read_url(self, **kwargs):
                return '/__fixtures/photo.svg'
        details.get_photo_storage = lambda: Storage()
        csp = re.search(r'add_header Content-Security-Policy "([^"]+)"',
                        (Path(__file__).resolve().parents[3] / 'deploy/web/nginx.conf').read_text()).group(1)

        @app.middleware('http')
        async def test_csp(request, call_next):
            response = await call_next(request)
            response.headers['Content-Security-Policy'] = csp
            return response

        @app.get('/__fixtures/photo.svg')
        def photo():
            return Response('<svg xmlns="http://www.w3.org/2000/svg" width="100" height="80"><rect width="100" height="80" fill="#4474c3"/></svg>', media_type='image/svg+xml')

        with tempfile.TemporaryDirectory(prefix='nw244-https-') as folder:
            from fastapi.staticfiles import StaticFiles
            assets = Path(__file__).resolve().parents[3] / 'web/dist/assets'
            app.mount('/assets', StaticFiles(directory=assets))
            marine = Path(folder) / 'marine'
            marine.mkdir()
            with tarfile.open(Path(__file__).resolve().parents[3] / 'deploy/marine/gebco-2026-v2.tar.gz') as archive:
                archive.extractall(marine, filter='data')
            app.mount('/api/v1/map/seafloor', StaticFiles(directory=marine))
            cert, key = Path(folder) / 'cert.pem', Path(folder) / 'key.pem'
            subprocess.run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-keyout', str(key),
                            '-out', str(cert), '-days', '1', '-subj', '/CN=localhost'], check=True, capture_output=True)
            uvicorn.run(app, host='127.0.0.1', port=8765, ssl_certfile=str(cert), ssl_keyfile=str(key), log_level='warning')
    finally:
        from app.infrastructure.database.connection import close_database_pools
        close_database_pools()
        with psycopg.connect(admin_dsn, autocommit=True) as conn:
            conn.execute(sql.SQL('DROP DATABASE {} WITH (FORCE)').format(sql.Identifier(name)))


if __name__ == '__main__':
    main()
