from fastapi import APIRouter

router = APIRouter(tags=["health"])


@router.get("/health")
def health_check() -> dict[str, str]:
    """Lightweight liveness probe for Docker and load balancers."""
    return {"status": "ok"}
