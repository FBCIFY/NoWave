"""Create the initial NoWave schema.

Revision ID: 20260917_0001
Revises:
Create Date: 2026-09-17
"""

from pathlib import Path

from alembic import op


revision = "20260917_0001"
down_revision = None
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
    op.get_bind().execution_options(no_parameters=True).exec_driver_sql(
        (SQL_MIGRATIONS / filename).read_text()
    )


def upgrade() -> None:
    execute_sql_file("001_schema.up.sql")


def downgrade() -> None:
    execute_sql_file("001_schema.down.sql")
