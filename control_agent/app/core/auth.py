from __future__ import annotations

from secrets import compare_digest

from fastapi import Depends, HTTPException, Request, status

from .config import Settings, get_settings


def require_bearer_token(
    request: Request, settings: Settings = Depends(get_settings)
) -> None:
    _require_one_of(
        request,
        expected_tokens=(settings.control_api_token,),
        unavailable_detail="Control agent token is not configured",
    )


def require_wake_bearer_token(
    request: Request, settings: Settings = Depends(get_settings)
) -> None:
    """Allow the full control credential or the WOL-only credential."""
    _require_one_of(
        request,
        expected_tokens=(settings.control_api_token, settings.wake_api_token),
        unavailable_detail="Wake API token is not configured",
    )


def _require_one_of(
    request: Request,
    *,
    expected_tokens: tuple[str | None, ...],
    unavailable_detail: str,
) -> None:
    configured_tokens = tuple(token for token in expected_tokens if token)
    if not configured_tokens:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=unavailable_detail,
        )

    raw_authorization = request.headers.get("Authorization", "")
    scheme, _, provided = raw_authorization.partition(" ")
    normalized = provided.strip()
    matches = [compare_digest(normalized, token) for token in configured_tokens]
    if scheme != "Bearer" or not any(matches):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Unauthorized",
        )
