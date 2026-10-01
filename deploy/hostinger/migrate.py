"""Run migrations with owner credentials, then grant only runtime privileges."""
from pathlib import Path
import subprocess
import sys

import psycopg
from psycopg import sql

from app.config.settings import get_settings

subprocess.run([sys.executable, '-m', 'alembic', '-c', 'alembic.ini', 'upgrade', 'head'], check=True)
with psycopg.connect(get_settings().require_database_url()) as conn:
    conn.execute('SELECT pg_advisory_xact_lock(6212091602)')
    if not conn.execute("SELECT 1 FROM pg_roles WHERE rolname = 'nowave_runtime'").fetchone():
        conn.execute('CREATE ROLE nowave_runtime LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS')
    password = Path('/run/secrets/db_runtime_password').read_text().strip()
    conn.execute(sql.SQL('ALTER ROLE nowave_runtime PASSWORD {}').format(sql.Literal(password)))
    conn.execute('REVOKE ALL ON DATABASE nowave FROM PUBLIC')
    conn.execute('GRANT CONNECT ON DATABASE nowave TO nowave_runtime')
    conn.execute('REVOKE CREATE ON SCHEMA public FROM PUBLIC')
    conn.execute('GRANT USAGE ON SCHEMA nowave, public TO nowave_runtime')
    conn.execute('GRANT SELECT, INSERT, UPDATE, DELETE ON nowave.users, nowave.reports, nowave.boats TO nowave_runtime')
    # Deferred integrity triggers read these tables when writing a report.
    conn.execute('GRANT SELECT, INSERT ON nowave.report_photos, nowave.report_positioning TO nowave_runtime')
    conn.execute('ALTER ROLE nowave_runtime SET statement_timeout = \'10s\'')
    conn.execute('ALTER ROLE nowave_runtime SET idle_in_transaction_session_timeout = \'15s\'')
print('Migrations and runtime grants applied.')
