from fastapi import APIRouter, Request
from fastapi.responses import JSONResponse

from app.database import ping

router = APIRouter(tags=["health"])


@router.get("/health")
def health_check() -> dict[str, str]:
    """Lightweight liveness probe for Docker and load balancers."""
    return {"status": "ok"}


@router.get("/ready", response_model=None)
def readiness_check(request: Request) -> dict[str, str] | JSONResponse:
    """Readiness probe — verifies PostgreSQL via Vault dynamic credentials."""
    db_conn = getattr(request.app.state, "db_conn", None)

    if db_conn is None:
        return JSONResponse(
            status_code=503,
            content={"status": "not_ready", "database": "disconnected"},
        )

    try:
        if ping(db_conn):
            return {"status": "ready", "database": "connected"}
    except Exception:
        # Do not expose database details through a public health endpoint.
        return JSONResponse(
            status_code=503,
            content={"status": "not_ready", "database": "error"},
        )

    return JSONResponse(
        status_code=503,
        content={"status": "not_ready", "database": "error"},
    )
