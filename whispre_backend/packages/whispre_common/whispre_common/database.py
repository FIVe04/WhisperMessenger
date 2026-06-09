from collections.abc import Callable, Generator
from contextlib import contextmanager
from functools import lru_cache

from sqlalchemy import Engine, create_engine
from sqlalchemy.orm import Session, sessionmaker


def normalize_postgres_dsn(postgres_dsn: str) -> str:
    if postgres_dsn.startswith('postgresql://'):
        return postgres_dsn.replace('postgresql://', 'postgresql+psycopg://', 1)
    return postgres_dsn


@lru_cache
def create_db_engine(postgres_dsn: str) -> Engine:
    return create_engine(
        normalize_postgres_dsn(postgres_dsn),
        pool_pre_ping=True,
        pool_size=5,
        max_overflow=10,
    )


def create_session_context(
    postgres_dsn: str,
    *,
    commit_on_success: bool,
) -> Callable[[], Generator[Session, None, None]]:
    session_factory = sessionmaker(
        bind=create_db_engine(postgres_dsn),
        autoflush=False,
        expire_on_commit=False,
    )

    @contextmanager
    def get_db() -> Generator[Session, None, None]:
        session = session_factory()
        try:
            yield session
            if commit_on_success:
                session.commit()
        except Exception:
            session.rollback()
            raise
        finally:
            session.close()

    return get_db
