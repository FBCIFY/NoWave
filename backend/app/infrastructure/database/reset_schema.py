"""Explicit, one-time production reset from blueway to an empty nowave schema."""

import argparse
from pathlib import Path

import psycopg

from app.config.settings import get_settings


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--confirm-drop-blueway", action="store_true", required=True)
    parser.add_argument("--expected-revision", required=True)
    args = parser.parse_args()
    schema_sql = (Path(__file__).parent / "migrations/001_schema.up.sql").read_text()
    with psycopg.connect(get_settings().require_database_url()) as conn:
        conn.execute("SELECT pg_advisory_xact_lock(6212091601)")
        if conn.execute("SELECT current_database()").fetchone() != ("nowave",):
            raise RuntimeError("Only the production database named nowave can be reset")
        if conn.execute("SELECT version_num FROM public.alembic_version").fetchall() != [
            (args.expected_revision,)
        ]:
            raise RuntimeError("Migration revision changed; inspect production before resetting")
        if conn.execute("SELECT to_regnamespace('blueway'), to_regnamespace('nowave')").fetchone() != (
            "blueway", None
        ):
            raise RuntimeError("Expected blueway to exist and nowave to be absent")
        # All destructive DDL, reconstruction, grants and the version update
        # share a single transaction: any failure restores the original schema.
        conn.execute("DROP SCHEMA blueway CASCADE")
        conn.execute(schema_sql.replace("blueway", "nowave"))
        conn.execute("ALTER TABLE nowave.users ALTER COLUMN email SET NOT NULL")
        conn.execute("GRANT USAGE ON SCHEMA nowave TO nowave_runtime")
        conn.execute(
            "GRANT SELECT, INSERT, UPDATE, DELETE ON nowave.users, nowave.reports TO nowave_runtime"
        )
        conn.execute("GRANT SELECT ON nowave.report_photos, nowave.report_positioning TO nowave_runtime")
        conn.execute(
            "UPDATE public.alembic_version SET version_num = %s",
            ("20260930_schema_nowave",),
        )
    print("Recreated the empty nowave schema with runtime grants.")


if __name__ == "__main__":
    main()
