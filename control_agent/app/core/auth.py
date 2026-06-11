from __future__ import annotations

from secrets import compare_digest

from fastapi import Depends, HTTPException, Request, status

from .config import Settings, get_settings


def require_bearer_token(
    request: Request, settings: Settings = Depends(get_settings)
) -> None:
    expected = settings.control_api_token
    if not expected:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Control agent token is not configured",
        )

    raw_authorization = request.headers.get("Authorization", "")
    scheme, _, provided = raw_authorization.partition(" ")
    if scheme != "Bearer" or not compare_digest(provided.strip(), expected):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Unauthorized",
        )
