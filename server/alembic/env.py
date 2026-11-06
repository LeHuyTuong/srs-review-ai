"""Alembic environment for the FastAPI business DB (ADR-0021).

The URL comes from ``DATABASE_URL`` via the app's own settings (server/.env
locally, the container environment in Docker) — never from alembic.ini, so no
password is committed. Run from ``server/``:

    .venv/Scripts/python -m alembic upgrade head      # Windows venv
    alembic upgrade head                              # inside the container
"""

from __future__ import annotations

from logging.config import fileConfig

from alembic import context
from sqlalchemy import pool

from app.infrastructure.db import Base, database_url, make_engine

config = context.config

if config.config_file_name is not None:
    fileConfig(config.config_file_name)

target_metadata = Base.metadata


def run_migrations_offline() -> None:
    """``alembic upgrade head --sql``: print the DDL instead of running it."""
    context.configure(
        url=database_url().render_as_string(hide_password=False),
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
        compare_type=True,
    )
    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    # NullPool: a migration is one short-lived connection, nothing to pool.
    connectable = make_engine(poolclass=pool.NullPool)
    with connectable.connect() as connection:
        context.configure(connection=connection, target_metadata=target_metadata, compare_type=True)
        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
