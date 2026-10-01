"""Verify repeated upgrades preserve the NoWave schema and its triggers."""

import psycopg
import pytest

from conftest import seed, upgrade_database


def test_schema_upgrade_preserves_rows_and_triggers(dsn):
    with psycopg.connect(dsn) as conn:
        ids = seed(conn)
    upgrade_database(dsn)
    with psycopg.connect(dsn) as conn:
        assert conn.execute("SELECT to_regnamespace('blueway')").fetchone() == (None,)
        assert conn.execute(
            "SELECT id FROM nowave.users WHERE id = %s", (ids["user"],)
        ).fetchone() == (ids["user"],)
        definitions = conn.execute(
            "SELECT pg_get_functiondef(p.oid) FROM pg_proc p "
            "JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'nowave'"
        ).fetchall()
        assert len(definitions) == 5
        assert all("blueway" not in definition for (definition,) in definitions)
        conn.execute("SELECT nowave.assert_photo_children(%s)", (ids["report"],))
        conn.execute(
            "UPDATE nowave.reports SET positioning_mode = 'photo' WHERE id = %s",
            (ids["manual"],),
        )
        with pytest.raises(psycopg.errors.CheckViolation):
            conn.commit()
