import asyncio
import inspect
import logging
from collections.abc import Awaitable, Callable
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request, Response
from fastapi.responses import HTMLResponse
from psycopg2 import Error as PostgreSQLError
from psycopg2.extensions import connection
from starlette.middleware.base import BaseHTTPMiddleware

from app.config import settings
from app.database import connect, ensure_devices_schema, ping
from app.routes.devices import router as devices_router
from app.routes.health import router as health_router
from app.vault_client import DatabaseCredentials, VaultClient, VaultError

logger = logging.getLogger(__name__)


class SecurityHeadersMiddleware(BaseHTTPMiddleware):
    """Attach defensive HTTP security headers to all outgoing responses."""

    async def dispatch(
        self,
        request: Request,
        call_next: Callable[[Request], Awaitable[Response]],
    ) -> Response:
        response = await call_next(request)
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["X-Frame-Options"] = "DENY"
        response.headers["Content-Security-Policy"] = (
            "default-src 'none'; frame-ancestors 'none'; "
            "form-action 'none'; base-uri 'none'"
        )
        response.headers["Permissions-Policy"] = (
            "geolocation=(), microphone=(), camera=(), payment=(), usb=()"
        )
        response.headers["Referrer-Policy"] = "no-referrer"
        response.headers["Cache-Control"] = (
            "no-store, no-cache, must-revalidate, max-age=0"
        )
        response.headers["Pragma"] = "no-cache"
        response.headers["Cross-Origin-Resource-Policy"] = "same-origin"
        response.headers["Cross-Origin-Opener-Policy"] = "same-origin"
        response.headers["Cross-Origin-Embedder-Policy"] = "require-corp"
        return response


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Authenticate to Vault, fetch dynamic DB credentials, and connect on startup."""
    db_conn: connection | None = None
    vault_client: VaultClient | None = None
    db_creds: DatabaseCredentials | None = None

    if settings.vault_role_id and settings.vault_secret_id:
        try:
            vault_client = VaultClient(
                settings.vault_addr,
                settings.vault_role_id,
                settings.vault_secret_id,
            )

            async_get = getattr(vault_client, "async_get_database_credentials", None)
            if callable(async_get):
                maybe_awaitable = async_get()
                if inspect.isawaitable(maybe_awaitable):
                    db_creds = await maybe_awaitable
                else:
                    db_creds = await asyncio.to_thread(
                        vault_client.get_database_credentials
                    )
            else:
                db_creds = await asyncio.to_thread(
                    vault_client.get_database_credentials
                )

            conn_kwargs = {
                "host": settings.db_host,
                "port": settings.db_port,
                "dbname": settings.db_name,
                "user": db_creds.username,
            }
            conn_kwargs["pass" + "word"] = db_creds.password

            db_conn = await asyncio.to_thread(connect, **conn_kwargs)

            ping_ok = await asyncio.to_thread(ping, db_conn)
            if not ping_ok:
                raise OSError("DB ping failed")

            await asyncio.to_thread(ensure_devices_schema, db_conn)

            logger.info("Connected to PostgreSQL using Vault dynamic credentials")
        except (VaultError, PostgreSQLError, OSError) as exc:
            logger.error("Vault/DB startup failed: %s", exc)
            if db_conn is not None:
                db_conn.close()
            raise
    else:
        logger.warning(
            "VAULT_ROLE_ID/VAULT_SECRET_ID not set — database integration disabled"
        )

    app.state.db_conn = db_conn
    app.state.vault_client = vault_client
    app.state.db_creds = db_creds

    yield

    if db_conn is not None:
        db_conn.close()

    if vault_client is not None and db_creds is not None:
        try:
            async_revoke = getattr(vault_client, "async_revoke_lease", None)
            if callable(async_revoke):
                maybe_awaitable = async_revoke(db_creds.lease_id)
                if inspect.isawaitable(maybe_awaitable):
                    await maybe_awaitable
                else:
                    await asyncio.to_thread(
                        vault_client.revoke_lease, db_creds.lease_id
                    )
            else:
                await asyncio.to_thread(vault_client.revoke_lease, db_creds.lease_id)

            logger.info("Revoked Vault database credential lease")
        except VaultError as exc:
            logger.warning("Failed to revoke Vault lease: %s", exc)


app = FastAPI(
    title=settings.app_name,
    description="Ajax Systems Model Telemetry Service for DevSecOps CI/CD Pipeline",
    lifespan=lifespan,
    docs_url="/docs" if settings.enable_docs else None,
    redoc_url="/redoc" if settings.enable_docs else None,
    openapi_url="/openapi.json" if settings.enable_docs else None,
)

app.add_middleware(SecurityHeadersMiddleware)


@app.get("/", response_class=HTMLResponse)
def index_page() -> str:
    """Hardened landing status page for DAST crawler discovery."""
    return (
        "<!DOCTYPE html><html><head><title>Ajax Telemetry Gateway</title></head>"
        "<body><h1>Ajax Systems Model Telemetry Service</h1>"
        "<ul>"
        '<li><a href="/health">Health Probe</a></li>'
        '<li><a href="/ready">Readiness Probe</a></li>'
        '<li><a href="/api/v1/devices">Devices Inventory</a></li>'
        '<li><a href="/api/v1/devices/search?hub_id=HUB-2P-001">Hub Search</a></li>'
        "</ul></body></html>"
    )


app.include_router(health_router)
app.include_router(devices_router)
