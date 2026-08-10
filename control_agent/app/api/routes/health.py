from __future__ import annotations

from datetime import datetime, timezone

from fastapi import APIRouter, Depends

from ...core.auth import require_wake_bearer_token
from ...core.config import Settings, get_settings
from ...models.health import HealthResponse

router = APIRouter(
    prefix="/health",
    tags=["health"],
    dependencies=[Depends(require_wake_bearer_token)],
)


@router.get("", response_model=HealthResponse)
def get_health(settings: Settings = Depends(get_settings)) -> HealthResponse:
    return HealthResponse(
        status="ok",
        app_name=settings.app_name,
        version=settings.app_version,
        timestamp=datetime.now(timezone.utc),
    )
