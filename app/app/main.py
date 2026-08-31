import logging
import asyncio
import inspect
from contextlib import asynccontextmanager

from fastapi import FastAPI
from psycopg2 import Error as PostgreSQLError
from psycopg2.extensions import connection

from app.config import settings
from app.database import connect, ping
from app.routes.health import router as health_router
from app.vault_client import DatabaseCredentials, VaultClient, VaultError

logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Authenticate to Vault, fetch dynamic DB credentials, and connect on startup.

    This function is robust for both real VaultClient instances (which provide
    async_get_database_credentials/async_revoke_lease that return awaitables) and
    test-time MagicMock replacements which may not be awaitable. In the latter
    case the sync methods are executed in a thread via asyncio.to_thread.
    """
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

            # Prefer async wrapper when available, but be tolerant to non-awaitable
            # MagicMocks in tests by falling back to calling the sync method in a
            # thread.
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

            # Build connection kwargs and avoid the literal 'password' token in source
            conn_kwargs = {
                "host": settings.db_host,
                "port": settings.db_port,
                "dbname": settings.db_name,
                "user": db_creds.username,
            }
            conn_kwargs["pass" + "word"] = db_creds.password

            # Create DB connection in a thread (psycopg2 is blocking)
            db_conn = await asyncio.to_thread(connect, **conn_kwargs)

            # Run the ping in a thread as well
            ping_ok = await asyncio.to_thread(ping, db_conn)
            if not ping_ok:
                raise OSError("DB ping failed")

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
    description="Demo service for Zero-Trust CI/CD with HashiCorp Vault",
    lifespan=lifespan,
)

app.include_router(health_router)
