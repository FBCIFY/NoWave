"""Move the application schema to nowave and repair trigger function references.

Revision ID: 20260930_schema_nowave
Revises: 20260920_0002
"""

from alembic import op


revision = "20260930_schema_nowave"
down_revision = "20260920_0002"
branch_labels = None
depends_on = None


def rename_schema(source: str, target: str) -> None:
    # These names are internal constants, never supplied by an API client.
    op.execute(f"ALTER SCHEMA {source} RENAME TO {target}")
    # PostgreSQL moves functions and preserves grants/dependencies when renaming
    # a schema, but does not rewrite PL/pgSQL bodies or function search_path.
    op.get_bind().execution_options(no_parameters=True).exec_driver_sql(
        f"""
        DO $rename$
        DECLARE definition text;
        BEGIN
            FOR definition IN
                SELECT pg_get_functiondef(p.oid)
                FROM pg_proc p
                JOIN pg_namespace n ON n.oid = p.pronamespace
                WHERE n.nspname = '{target}' AND p.prokind = 'f'
            LOOP
                EXECUTE replace(
                    replace(definition, '{source}.', '{target}.'),
                    'SET search_path TO ''{source}'',',
                    'SET search_path TO ''{target}'','
                );
            END LOOP;
        END $rename$;
        """
    )


def upgrade() -> None:
    rename_schema("blueway", "nowave")


def downgrade() -> None:
    rename_schema("nowave", "blueway")
