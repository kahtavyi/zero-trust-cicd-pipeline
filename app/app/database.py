"""PostgreSQL helpers for dynamic credentials from Vault."""

from psycopg2.extensions import connection
from psycopg2 import connect as pg_connect


def connect(
    *,
    host: str,
    port: int,
    dbname: str,
    user: str,
    password: str,
) -> connection:
    return pg_connect(
        host=host,
        port=port,
        dbname=dbname,
        user=user,
        password=password,
        connect_timeout=5,
    )


def ping(conn: connection) -> bool:
    with conn.cursor() as cursor:
        cursor.execute("SELECT 1")
        return cursor.fetchone()[0] == 1
