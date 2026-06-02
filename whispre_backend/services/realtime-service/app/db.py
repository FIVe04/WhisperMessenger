from contextlib import contextmanager

from psycopg import Connection
from psycopg.rows import dict_row

from .config import settings


@contextmanager
def get_db() -> Connection:
    conn = Connection.connect(settings.postgres_dsn, row_factory=dict_row)
    try:
        yield conn
    finally:
        conn.close()
