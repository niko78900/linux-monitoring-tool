from __future__ import annotations

import logging
from datetime import datetime, timezone

from fastapi import APIRouter, Body, Depends, HTTPException, status

from ...core.auth import require_bearer_token
from ...core.config import Settings, get_settings
from ...core.rate_limit import RateLimitError, rate_limiter
from ...models.actions import WakeActionResponse
from ...services.wake_on_lan import send_magic_packet

logger = logging.getLogger(__name__)

router = APIRouter(
    prefix="/actions",
    tags=["actions"],
    dependencies=[Depends(require_bearer_token)],
)


@router.post(
    "/wake-main-pc",
    response_model=WakeActionResponse,
    status_code=status.HTTP_202_ACCEPTED,
)
def wake_main_pc(
    _: dict | None = Body(default=None),
    settings: Settings = Depends(get_settings),
) -> WakeActionResponse:
    try:
        rate_limiter.check("wake-main-pc", settings.wake_rate_limit_seconds)
    except RateLimitError as error:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail=f"Action is temporarily rate limited. Retry in {error.retry_after_seconds} seconds.",
        ) from error

    try:
        send_magic_packet(
            settings.main_pc_mac,
            settings.wake_broadcast_host,
            settings.wake_port,
        )
    except Exception as error:  # pragma: no cover - guarded by tests with monkeypatch
        logger.exception("Wake Main PC failed")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Action failed",
        ) from error

    logger.info("Wake Main PC accepted")
    return WakeActionResponse(
        action="wake-main-pc",
        status="accepted",
        target="main_pc",
        requested_at=datetime.now(timezone.utc),
        rate_limit_seconds=settings.wake_rate_limit_seconds,
    )
