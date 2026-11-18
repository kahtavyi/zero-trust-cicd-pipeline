"""Ajax Systems model telemetry endpoints (Phase B — hardened implementation)."""

import socket
from typing import Annotated, Any

from fastapi import APIRouter, Query, Request
from pydantic import BaseModel, Field

from app.database import SEED_DEVICES

router = APIRouter(prefix="/api/v1", tags=["devices"])


class PingRequest(BaseModel):
    target: str = Field(
        default="127.0.0.1",
        min_length=1,
        max_length=64,
        pattern=r"^[a-zA-Z0-9.-]+$",
        description="Hostname or IPv4 address of the Ajax hub node.",
    )


def _row_to_device(row: tuple[Any, ...]) -> dict[str, Any]:
    return {
        "hub_id": str(row[0]),
        "device_name": str(row[1]),
        "device_type": str(row[2]),
        "firmware_version": str(row[3]),
        "status": str(row[4]),
        "battery_level": int(row[5]),
    }


@router.get("/devices")
def list_devices(request: Request) -> dict[str, Any]:
    """Return all registered Ajax security devices from PostgreSQL."""
    db_conn = getattr(request.app.state, "db_conn", None)
    if db_conn is None:
        devices = [_row_to_device(row) for row in SEED_DEVICES]
        return {"count": len(devices), "source": "fallback", "devices": devices}

    with db_conn.cursor() as cursor:
        cursor.execute(
            """
            SELECT hub_id, device_name, device_type, firmware_version, status, battery_level
            FROM public.devices
            ORDER BY id ASC
            """
        )
        rows = cursor.fetchall()

    devices = [_row_to_device(row) for row in rows]
    return {"count": len(devices), "source": "postgresql", "devices": devices}


@router.get("/devices/search")
def search_devices(
    request: Request,
    hub_id: Annotated[
        str,
        Query(min_length=1, max_length=64, pattern=r"^[A-Z0-9-]+$"),
    ],
) -> dict[str, Any]:
    """Search Ajax device by hub_id using parameterized SQL queries."""
    db_conn = getattr(request.app.state, "db_conn", None)
    if db_conn is None:
        matched = [_row_to_device(row) for row in SEED_DEVICES if row[0] == hub_id]
        return {"count": len(matched), "devices": matched}

    with db_conn.cursor() as cursor:
        cursor.execute(
            """
            SELECT hub_id, device_name, device_type, firmware_version, status, battery_level
            FROM public.devices
            WHERE hub_id = %s
            """,
            (hub_id,),
        )
        rows = cursor.fetchall()

    devices = [_row_to_device(row) for row in rows]
    return {"count": len(devices), "devices": devices}


@router.post("/diagnostics/ping")
def ping_hub_node(payload: PingRequest) -> dict[str, Any]:
    """Safe network resolution check without OS shell invocation."""
    try:
        resolved = socket.getaddrinfo(payload.target, None)
        reachable = len(resolved) > 0
    except OSError:
        reachable = False

    return {
        "target": payload.target,
        "exit_code": 0 if reachable else 1,
        "output": f"Node {payload.target} verified via safe socket resolver",
    }
