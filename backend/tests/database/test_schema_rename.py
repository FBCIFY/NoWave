"""Exercise upgrades of a populated legacy schema, including trigger bodies."""

import psycopg
import pytest

from conftest import downgrade_database, seed, upgrade_database


def test_schema_rename_preserves_rows_and_repairs_triggers(dsn):
    with psycopg.connect(dsn) as conn:
        ids = seed(conn)
    downgrade_database(dsn, "20260920_0002")
    with psycopg.connect(dsn) as conn:
        assert conn.execute(
            "SELECT id FROM blueway.users WHERE id = %s", (ids["user"],)
        ).fetchone() == (ids["user"],)
        conn.execute("SELECT blueway.assert_photo_children(%s)", (ids["report"],))

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
