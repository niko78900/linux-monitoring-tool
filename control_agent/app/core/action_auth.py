from __future__ import annotations

from ipaddress import ip_address
from secrets import compare_digest
from typing import Annotated

from fastapi import Depends, HTTPException, Request, Security, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from .action_config import ActionServiceSettings

dashboard_action_bearer = HTTPBearer(
    auto_error=False,
    scheme_name="DashboardControlActionBearer",
    description="Dedicated bearer credential for the Dashboard action service.",
)


def get_request_action_settings(request: Request) -> ActionServiceSettings:
    return request.app.state.action_settings


def require_allowed_action_source(
    request: Request,
    settings: ActionServiceSettings = Depends(get_request_action_settings),
) -> None:
    client_host = request.client.host if request.client is not None else ""
    try:
        client_address = ip_address(client_host)
    except ValueError as error:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND) from error

    if not any(client_address in network for network in settings.allowed_networks):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND)


def require_dashboard_action_token(
    credentials: Annotated[
        HTTPAuthorizationCredentials | None,
        Security(dashboard_action_bearer),
    ],
    settings: ActionServiceSettings = Depends(get_request_action_settings),
) -> None:
    expected = settings.token
    if expected is None:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Action service authentication is unavailable",
        )

    supplied = credentials.credentials if credentials is not None else ""
    scheme = credentials.scheme if credentials is not None else ""
    if scheme.lower() != "bearer" or not compare_digest(supplied, expected):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Unauthorized",
            headers={"WWW-Authenticate": "Bearer"},
        )
