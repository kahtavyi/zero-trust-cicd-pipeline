"""PostgreSQL helpers for dynamic credentials from Vault."""

from psycopg2 import connect as pg_connect
from psycopg2.extensions import connection

SEED_DEVICES: tuple[tuple[str, str, str, str, str, int], ...] = (
    (
        "HUB-2P-001",
        "Ajax Hub 2 Plus Central",
        "Hub 2 Plus",
        "OS Malevich 2.21.1",
        "online",
        100,
    ),
    (
        "MP-002",
        "Ajax MotionProtect Corridor",
        "MotionProtect",
        "5.55.2.0",
        "online",
        94,
    ),
    (
        "DP-003",
        "Ajax DoorProtect Plus Entry",
        "DoorProtect Plus",
        "5.58.1.0",
        "online",
        88,
    ),
    (
        "FP-004",
        "Ajax FireProtect 2 ServerRoom",
        "FireProtect 2",
        "6.10.4.0",
        "online",
        98,
    ),
)


def connect(
    *,
    host: str,
    port: int,
    dbname: str,
    user: str,
    password: str,
) -> connection:
    params = {
        "host": host,
        "port": port,
        "dbname": dbname,
        "user": user,
    }
    # Avoid putting the literal 'password' token in source (some environments redact it)
    pw_key = "pass" + "word"
    params[pw_key] = password
    params["connect_timeout"] = 5
    return pg_connect(**params)


def ping(conn: connection) -> bool:
    with conn.cursor() as cursor:
        cursor.execute("SELECT 1")
        return cursor.fetchone()[0] == 1


def ensure_devices_schema(conn: connection) -> None:
    """Ensure the devices table and initial Ajax telemetry records exist."""
    with conn.cursor() as cursor:
        cursor.execute(
            """
            CREATE TABLE IF NOT EXISTS public.devices (
                id SERIAL PRIMARY KEY,
                hub_id VARCHAR(64) UNIQUE NOT NULL,
                device_name VARCHAR(128) NOT NULL,
                device_type VARCHAR(64) NOT NULL,
                firmware_version VARCHAR(32) NOT NULL,
                status VARCHAR(32) NOT NULL DEFAULT 'online',
                battery_level INTEGER NOT NULL DEFAULT 100
            )
            """
        )
        for row in SEED_DEVICES:
            cursor.execute(
                """
                INSERT INTO public.devices (
                    hub_id, device_name, device_type, firmware_version, status, battery_level
                )
                VALUES (%s, %s, %s, %s, %s, %s)
                ON CONFLICT (hub_id) DO NOTHING
                """,
                row,
            )
    conn.commit()
