"""Clean legacy nationalities and enforce ISO alpha-2 format.

Revision ID: 20261007_0002
Revises: 20260917_0001
Create Date: 2026-10-07
"""

from alembic import op


revision = "20261007_0002"
down_revision = "20260917_0001"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Legacy values made only of two ASCII letters are recoverable.
    op.execute(
        """
        UPDATE nowave.users
        SET nationality = UPPER(nationality)
        WHERE nationality IS NOT NULL
          AND nationality ~ '^[A-Za-z]{2}$'
        """
    )

    # Other legacy values cannot safely be mapped to an ISO alpha-2 code.
    op.execute(
        """
        UPDATE nowave.users
        SET nationality = NULL
        WHERE nationality IS NOT NULL
          AND nationality !~ '^[A-Z]{2}$'
        """
    )

    op.create_check_constraint(
        "users_nationality_iso_alpha2_check",
        "users",
        "nationality IS NULL OR nationality ~ '^[A-Z]{2}$'",
        schema="nowave",
    )


def downgrade() -> None:
    op.drop_constraint(
        "users_nationality_iso_alpha2_check",
        "users",
        schema="nowave",
        type_="check",
    )
