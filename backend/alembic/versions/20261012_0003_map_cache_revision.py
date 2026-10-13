"""Track committed report changes for bounded, immediately invalidated tile caches."""

from alembic import op

revision = "20261012_0003"
down_revision = "20261007_0002"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("""
        CREATE TABLE nowave.map_cache_revision (
            singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
            revision uuid NOT NULL DEFAULT gen_random_uuid()
        );
        INSERT INTO nowave.map_cache_revision (singleton) VALUES (true);
        CREATE FUNCTION nowave.invalidate_map_cache() RETURNS trigger
        LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
        BEGIN
            UPDATE nowave.map_cache_revision SET revision = gen_random_uuid()
            WHERE singleton;
            RETURN NULL;
        END;
        $$;
        REVOKE ALL ON FUNCTION nowave.invalidate_map_cache() FROM PUBLIC;
        CREATE TRIGGER reports_map_cache_revision
        AFTER INSERT OR UPDATE OR DELETE OR TRUNCATE ON nowave.reports
        FOR EACH STATEMENT EXECUTE FUNCTION nowave.invalidate_map_cache();
    """)


def downgrade() -> None:
    op.execute("""
        DROP TRIGGER reports_map_cache_revision ON nowave.reports;
        DROP FUNCTION nowave.invalidate_map_cache();
        DROP TABLE nowave.map_cache_revision;
    """)
