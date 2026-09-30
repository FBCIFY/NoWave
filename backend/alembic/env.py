"""Alembic runtime configuration for the NoWave PostgreSQL database."""

from logging.config import fileConfig

from alembic import context
from sqlalchemy import engine_from_config, pool
from app.config.settings import get_settings


config = context.config
if config.config_file_name:
    fileConfig(config.config_file_name)

target_metadata = None
LOCK_ID = 6212091601


def database_url() -> str:
    url = get_settings().database_url or config.get_main_option("sqlalchemy.url")
    if not url:
        raise RuntimeError("DATABASE_URL must be set before running Alembic")
    if url.startswith("postgresql://"):
        return url.replace("postgresql://", "postgresql+psycopg://", 1)
    return url


def run_migrations_offline() -> None:
    context.configure(
        url=database_url(),
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
        version_table_schema="public",
    )
    with context.begin_transaction():
        context.run_migrations()


def run_with_connection(connection) -> None:
    with connection.begin():
        # Serialise deployments so two instances cannot apply the same revision.
        connection.exec_driver_sql(
            "SELECT pg_advisory_xact_lock(%s)", (LOCK_ID,)
        )
        # Configure after acquiring the lock so Alembic reads the current
        # revision only after any competing deployment has committed.
        context.configure(
            connection=connection,
            target_metadata=target_metadata,
            version_table_schema="public",
            transactional_ddl=True,
        )
        with context.begin_transaction():
            context.run_migrations()


def run_migrations_online() -> None:
    supplied_connection = config.attributes.get("connection")
    if supplied_connection is not None:
        run_with_connection(supplied_connection)
        return

    configuration = config.get_section(config.config_ini_section) or {}
    configuration["sqlalchemy.url"] = database_url()
    connectable = engine_from_config(
        configuration,
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )
    with connectable.connect() as connection:
        run_with_connection(connection)


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
