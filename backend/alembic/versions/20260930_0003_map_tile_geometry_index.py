"""Index report geometry for worldwide map tile lookups.

Revision ID: 20260930_0003
Revises: 20260930_schema_nowave
"""

from alembic import op


revision = "20260930_0003"
down_revision = "20260930_schema_nowave"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        "CREATE INDEX reports_final_position_geometry_gist "
        "ON nowave.reports USING gist ((final_position::geometry))"
    )


def downgrade() -> None:
    op.execute("DROP INDEX nowave.reports_final_position_geometry_gist")
