from __future__ import annotations

from datetime import datetime, timezone
from ipaddress import ip_address
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, Request, Response, status

from ..core.action_auth import (
    require_allowed_action_source,
    require_dashboard_action_token,
)
from ..core.config import get_settings
from ..models.dashboard_actions import (
    ActionAcceptedResponse,
    ActionHealthResponse,
    ActionHistoryResponse,
    ActionRecordResponse,
    ActionRequest,
    CapabilitiesResponse,
    ServiceCapability,
    ServicesCapabilityResponse,
    WakeCapability,
)
from ..services.action_service import ActionQueueFullError, DashboardActionService
from ..services.action_store import BusyTargetError

router = APIRouter(
    dependencies=[
        Depends(require_allowed_action_source),
        Depends(require_dashboard_action_token),
    ]
)


def get_dashboard_action_service(request: Request) -> DashboardActionService:
    return request.app.state.dashboard_action_service


@router.get("/health", response_model=ActionHealthResponse, tags=["actions"])
def get_health(
    action_service: DashboardActionService = Depends(get_dashboard_action_service),
) -> ActionHealthResponse:
    database_healthy = action_service.store.quick_check()
    workers_healthy = action_service.workers_healthy
    healthy = database_healthy and workers_healthy
    return ActionHealthResponse(
        status="ok" if healthy else "degraded",
        app_name="Linux Monitor Dashboard Action Service",
        version=get_settings().app_version,
        action_service_available=healthy,
        registry_loaded=True,
        registry_service_count=len(action_service.registry.services),
        wake_available=action_service.registry.get_wake_target() is not None,
        action_database_healthy=database_healthy,
        workers_healthy=workers_healthy,
        timestamp=datetime.now(timezone.utc),
    )


@router.get("/capabilities", response_model=CapabilitiesResponse, tags=["actions"])
def get_capabilities(
    action_service: DashboardActionService = Depends(get_dashboard_action_service),
) -> CapabilitiesResponse:
    return CapabilitiesResponse(
        services=_service_capabilities(action_service),
        wake_main_pc=_wake_capability(action_service),
    )


@router.get("/services", response_model=ServicesCapabilityResponse, tags=["actions"])
def get_services(
    action_service: DashboardActionService = Depends(get_dashboard_action_service),
) -> ServicesCapabilityResponse:
    return ServicesCapabilityResponse(services=_service_capabilities(action_service))


@router.get(
    "/services/{service_id}",
    response_model=ServiceCapability,
    tags=["actions"],
)
def get_service(
    service_id: str,
    action_service: DashboardActionService = Depends(get_dashboard_action_service),
) -> ServiceCapability:
    service = action_service.registry.get_service(service_id)
    if service is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Service not found",
        )
    return _service_capability(
        service,
        busy=service.id in action_service.store.busy_targets(),
    )


@router.get("/actions", response_model=ActionHistoryResponse, tags=["actions"])
def get_actions(
    limit: int = Query(default=50, ge=1, le=200),
    action_service: DashboardActionService = Depends(get_dashboard_action_service),
) -> ActionHistoryResponse:
    return ActionHistoryResponse(actions=action_service.store.list(limit=limit))


@router.get(
    "/actions/{action_id}",
    response_model=ActionRecordResponse,
    tags=["actions"],
)
def get_action(
    action_id: UUID,
    action_service: DashboardActionService = Depends(get_dashboard_action_service),
) -> ActionRecordResponse:
    record = action_service.store.get(str(action_id))
    if record is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Action not found",
        )
    return record


@router.post(
    "/services/{service_id}/actions/{action}",
    response_model=ActionAcceptedResponse,
    status_code=status.HTTP_202_ACCEPTED,
    tags=["actions"],
)
async def post_service_action(
    service_id: str,
    action: str,
    action_request: ActionRequest,
    request: Request,
    response: Response,
    action_service: DashboardActionService = Depends(get_dashboard_action_service),
) -> ActionAcceptedResponse:
    service = action_service.registry.get_service(service_id)
    if service is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Service not found",
        )
    if action not in {"start", "stop", "restart"} or action not in service.allowed_actions:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Action is not allowed for this service",
        )
    try:
        accepted = action_service.accept_service_action(
            service=service,
            action=action,
            action_request=action_request,
            source_address=_source_address(request),
        )
    except BusyTargetError as error:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Target already has an active action",
        ) from error
    except ActionQueueFullError as error:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Action queue is full",
        ) from error
    response.headers["Location"] = accepted.polling_location
    return accepted


@router.post(
    "/actions/wake-main-pc",
    response_model=ActionAcceptedResponse,
    status_code=status.HTTP_202_ACCEPTED,
    tags=["actions"],
)
async def post_wake_main_pc(
    action_request: ActionRequest,
    request: Request,
    response: Response,
    action_service: DashboardActionService = Depends(get_dashboard_action_service),
) -> ActionAcceptedResponse:
    wake_target = action_service.registry.get_wake_target()
    if wake_target is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Wake target is unavailable",
        )
    try:
        accepted = action_service.accept_wake_action(
            target=wake_target,
            action_request=action_request,
            source_address=_source_address(request),
        )
    except BusyTargetError as error:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Target already has an active action",
        ) from error
    except ActionQueueFullError as error:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Action queue is full",
        ) from error
    response.headers["Location"] = accepted.polling_location
    return accepted


def _service_capabilities(
    action_service: DashboardActionService,
) -> list[ServiceCapability]:
    busy_targets = action_service.store.busy_targets()
    return [
        _service_capability(service, busy=service.id in busy_targets)
        for service in action_service.registry.services
    ]


def _service_capability(service, *, busy: bool) -> ServiceCapability:
    return ServiceCapability(
        id=service.id,
        name=service.name,
        kind=service.kind,
        allowed_actions=list(service.allowed_actions),
        confirmation_level=service.confirmation_level,
        busy=busy,
    )


def _wake_capability(
    action_service: DashboardActionService,
) -> WakeCapability | None:
    target = action_service.registry.get_wake_target()
    if target is None:
        return None
    return WakeCapability(
        name=target.name,
        available=target.id not in action_service.store.busy_targets(),
        confirmation_level=target.confirmation_level,
    )


def _source_address(request: Request) -> str:
    client_host = request.client.host if request.client is not None else ""
    return str(ip_address(client_host))
