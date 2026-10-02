"""Add spatial index used by MVT map tiles.

Revision ID: 20261002_0002
Revises: 20260917_0001
Create Date: 2026-10-02
"""

from pathlib import Path

from alembic import op


revision = "20261002_0002"
down_revision = "20260917_0001"
branch_labels = None
depends_on = None

SQL_MIGRATIONS = (
    Path(__file__).resolve().parents[2]
    / "app"
    / "infrastructure"
    / "database"
    / "migrations"
)


def execute_sql_file(filename: str) -> None:
    op.get_bind().execution_options(
        no_parameters=True
    ).exec_driver_sql(
        (SQL_MIGRATIONS / filename).read_text()
    )


def upgrade() -> None:
    execute_sql_file(
        "002_map_tile_index.up.sql"
    )


def downgrade() -> None:
    execute_sql_file(
        "002_map_tile_index.down.sql"
    )
