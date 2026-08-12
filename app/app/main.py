from contextlib import asynccontextmanager

from fastapi import FastAPI

from app.config import settings
from app.routes.health import router as health_router


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Startup/shutdown hooks — Vault DB integration will be added in Stage 2."""
    yield


app = FastAPI(
    title=settings.app_name,
    description="Demo service for Zero-Trust CI/CD with HashiCorp Vault",
    lifespan=lifespan,
)

app.include_router(health_router)
