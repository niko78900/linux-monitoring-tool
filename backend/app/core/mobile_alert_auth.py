from __future__ import annotations

from fastapi import Depends, HTTPException, Request, status

from app.core.config import Settings, get_settings


def require_mobile_alert_token(
    request: Request,
    settings: Settings = Depends(get_settings),
) -> None:
    _require_scoped_token(
        request=request,
        configured_token=settings.mobile_alert_api_token,
        missing_detail="Mobile alert API token is not configured",
    )


def require_alert_consumer_token(
    request: Request,
    settings: Settings = Depends(get_settings),
) -> None:
    _require_scoped_token(
        request=request,
        configured_token=settings.alert_consumer_api_token,
        missing_detail="Alert consumer API token is not configured",
    )


def _require_scoped_token(
    *,
    request: Request,
    configured_token: str | None,
    missing_detail: str,
) -> None:
    if configured_token is None:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=missing_detail,
        )

    authorization = request.headers.get("Authorization", "")
    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or token.strip() != configured_token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid bearer token",
            headers={"WWW-Authenticate": "Bearer"},
        )
