"""Declarative base, constraint naming and engine factory."""

from __future__ import annotations

from typing import Any

from sqlalchemy import Engine, MetaData, create_engine
from sqlalchemy.engine import URL, make_url
from sqlalchemy.orm import DeclarativeBase

from app.config.settings import get_settings

# Deterministic constraint names: Alembic can only drop/alter a constraint it
# can name, and Postgres' auto-generated names differ between versions.
NAMING_CONVENTION = {
    "ix": "ix_%(column_0_label)s",
    "uq": "uq_%(table_name)s_%(column_0_name)s",
    "ck": "ck_%(table_name)s_%(constraint_name)s",
    "fk": "fk_%(table_name)s_%(column_0_name)s_%(referred_table_name)s",
    "pk": "pk_%(table_name)s",
}


class Base(DeclarativeBase):
    metadata = MetaData(naming_convention=NAMING_CONVENTION)


def database_url(raw: str | None = None) -> URL:
    """The configured ``DATABASE_URL`` with the Psycopg 3 driver made explicit.

    A bare ``postgresql://`` URL makes SQLAlchemy pick psycopg2, which is not
    installed (requirements pin psycopg 3).
    """
    value = raw if raw is not None else get_settings().database_url
    if not value:
        raise RuntimeError("DATABASE_URL is not set (server/.env or the container environment).")
    url = make_url(value)
    if url.drivername in {"postgres", "postgresql"}:
        url = url.set(drivername="postgresql+psycopg")
    return url


CONNECT_TIMEOUT_S = 10
"""Without it psycopg can wait forever on one address: on Windows ``localhost``
resolves to ``::1`` first and a Docker-published port may accept there and never
answer (seen 2026-11-06 — ``alembic`` hung with no output). With a timeout,
psycopg gives up on that address and tries ``127.0.0.1``."""


def make_engine(raw: str | None = None, **kwargs: Any) -> Engine:
    connect_args = {"connect_timeout": CONNECT_TIMEOUT_S, **kwargs.pop("connect_args", {})}
    return create_engine(database_url(raw), pool_pre_ping=True, connect_args=connect_args, **kwargs)
