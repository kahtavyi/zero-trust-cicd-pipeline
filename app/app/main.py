import logging
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
            db_creds = vault_client.get_database_credentials()
            db_conn = connect(
                host=settings.db_host,
                port=settings.db_port,
                dbname=settings.db_name,
                user=db_creds.username,
                password=db_creds.password,
            )
            ping(db_conn)
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
            vault_client.revoke_lease(db_creds.lease_id)
            logger.info("Revoked Vault database credential lease")
        except VaultError as exc:
            logger.warning("Failed to revoke Vault lease: %s", exc)


app = FastAPI(
    title=settings.app_name,
    description="Demo service for Zero-Trust CI/CD with HashiCorp Vault",
    lifespan=lifespan,
)

app.include_router(health_router)
