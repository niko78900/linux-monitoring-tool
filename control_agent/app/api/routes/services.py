from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, status

from ...core.auth import require_bearer_token
from ...core.config import Settings, get_settings
from ...models.services import (
    ManagedServiceStatus,
    ManagedServicesResponse,
    ServiceAction,
    ServiceActionResponse,
)
from ...services.service_registry import (
    execute_service_action,
    get_service_status,
    list_service_statuses,
    load_service_registry,
)

router = APIRouter(
    prefix="/services",
    tags=["services"],
    dependencies=[Depends(require_bearer_token)],
)


@router.get("", response_model=ManagedServicesResponse)
def get_services(settings: Settings = Depends(get_settings)) -> ManagedServicesResponse:
    services = _load_services(settings)
    return list_service_statuses(services)


@router.get("/{service_id}", response_model=ManagedServiceStatus)
def get_service(
    service_id: str,
    settings: Settings = Depends(get_settings),
) -> ManagedServiceStatus:
    services = _load_services(settings)
    service = next((item for item in services if item.id == service_id), None)
    if service is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Service not found",
        )
    return get_service_status(service)


@router.post(
    "/{service_id}/actions/{action}",
    response_model=ServiceActionResponse,
    status_code=status.HTTP_202_ACCEPTED,
)
def post_service_action(
    service_id: str,
    action: ServiceAction,
    settings: Settings = Depends(get_settings),
) -> ServiceActionResponse:
    services = _load_services(settings)
    try:
        record = execute_service_action(
            services,
            service_id=service_id,
            action=action,
            helper_path=settings.service_control_helper_path,
            timeout_seconds=settings.service_command_timeout_seconds,
        )
    except LookupError as error:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Service not found",
        ) from error
    except PermissionError as error:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Action is not allowed for this service",
        ) from error
    except RuntimeError as error:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=str(error),
        ) from error

    return ServiceActionResponse(
        service_id=service_id,
        action=action,
        status=record.status,
        requested_at=record.requested_at,
        detail=record.detail,
    )


def _load_services(settings: Settings):
    try:
        return load_service_registry(settings.services_config_path)
    except ValueError as error:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Services configuration is invalid",
        ) from error
