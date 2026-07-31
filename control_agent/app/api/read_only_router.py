from __future__ import annotations

import os
import shutil
from datetime import datetime, timezone
from pathlib import Path
from typing import Callable

from fastapi import APIRouter, Depends, HTTPException, status

from ..core.config import Settings, get_settings
from ..core.read_only_auth import (
    require_allowed_dashboard_source,
    require_dashboard_read_token,
)
from ..models.devices import DevicesResponse
from ..models.hosts import ManagedHostStatus, ManagedHostsResponse
from ..models.read_only import (
    DashboardReadHealthResponse,
    DiscoveryAvailability,
    ReadOnlyDiscoveryAvailability,
)
from ..models.services import ManagedServiceStatus, ManagedServicesResponse, ServiceConfig
from ..services.device_probe import load_known_devices, probe_known_devices
from ..services.managed_hosts import load_managed_hosts, probe_managed_hosts
from ..services.service_registry import (
    get_service_status,
    list_service_statuses,
    load_service_registry,
)
from ..services.tailscale_peers import read_tailscale_peers

router = APIRouter(
    dependencies=[
        Depends(require_allowed_dashboard_source),
        Depends(require_dashboard_read_token),
    ]
)


@router.get("/health", response_model=DashboardReadHealthResponse, tags=["read-only"])
def get_read_only_health(
    settings: Settings = Depends(get_settings),
) -> DashboardReadHealthResponse:
    devices_state = _configuration_state(
        load_known_devices,
        settings.known_devices_config_path,
    )
    hosts_state = _configuration_state(
        load_managed_hosts,
        settings.managed_hosts_config_path,
    )

    try:
        services = load_service_registry(settings.services_config_path)
        services_state: DiscoveryAvailability = "available"
    except ValueError:
        services = []
        services_state = "unavailable"

    if services_state == "unavailable":
        docker_state: DiscoveryAvailability = "unavailable"
    elif not any(service.adapter == "docker" for service in services):
        docker_state = "not_required"
    elif _docker_runtime_available():
        docker_state = "available"
    else:
        docker_state = "partial"

    availability = ReadOnlyDiscoveryAvailability(
        devices=devices_state,
        hosts=hosts_state,
        services=services_state,
        docker_runtime=docker_state,
    )
    bridge_status = (
        "ok"
        if all(
            value in {"available", "not_required"}
            for value in availability.model_dump().values()
        )
        else "degraded"
    )
    return DashboardReadHealthResponse(
        status=bridge_status,
        app_name="Linux Monitor Dashboard Read-Only Bridge",
        version=settings.app_version,
        timestamp=datetime.now(timezone.utc),
        discovery=availability,
    )


@router.get("/devices", response_model=DevicesResponse, tags=["read-only"])
async def get_read_only_devices(
    settings: Settings = Depends(get_settings),
) -> DevicesResponse:
    try:
        configs = load_known_devices(settings.known_devices_config_path)
    except ValueError as error:
        raise _discovery_unavailable("Device") from error

    response = await probe_known_devices(
        configs,
        tailscale_peers=read_tailscale_peers(),
    )
    for device in response.devices:
        device.wol_enabled = False
        device.wake_action = None
    return response


async def _observe_hosts(settings: Settings) -> ManagedHostsResponse:
    try:
        configs = load_managed_hosts(settings.managed_hosts_config_path)
    except ValueError as error:
        raise _discovery_unavailable("Host") from error
    return await probe_managed_hosts(
        configs,
        tailscale_peers=read_tailscale_peers(),
    )


@router.get("/hosts", response_model=ManagedHostsResponse, tags=["read-only"])
async def get_read_only_hosts(
    settings: Settings = Depends(get_settings),
) -> ManagedHostsResponse:
    return await _observe_hosts(settings)


@router.get("/hosts/{host_id}", response_model=ManagedHostStatus, tags=["read-only"])
async def get_read_only_host(
    host_id: str,
    settings: Settings = Depends(get_settings),
) -> ManagedHostStatus:
    response = await _observe_hosts(settings)
    for host in response.hosts:
        if host.id == host_id:
            return host
    raise HTTPException(
        status_code=status.HTTP_404_NOT_FOUND,
        detail="Managed host not found",
    )


def _load_services(settings: Settings) -> list[ServiceConfig]:
    try:
        return load_service_registry(settings.services_config_path)
    except ValueError as error:
        raise _discovery_unavailable("Service") from error


def _remove_service_actions(status_value: ManagedServiceStatus) -> ManagedServiceStatus:
    status_value.allowed_actions = []
    status_value.last_action = None
    return status_value


@router.get("/services", response_model=ManagedServicesResponse, tags=["read-only"])
def get_read_only_services(
    settings: Settings = Depends(get_settings),
) -> ManagedServicesResponse:
    response = list_service_statuses(_load_services(settings), action_store=None)
    response.services = [_remove_service_actions(item) for item in response.services]
    return response


@router.get(
    "/services/{service_id}",
    response_model=ManagedServiceStatus,
    tags=["read-only"],
)
def get_read_only_service(
    service_id: str,
    settings: Settings = Depends(get_settings),
) -> ManagedServiceStatus:
    service = next(
        (item for item in _load_services(settings) if item.id == service_id),
        None,
    )
    if service is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Service not found",
        )
    return _remove_service_actions(get_service_status(service, action_store=None))


def _configuration_state(
    loader: Callable[[Path], list[object]],
    path: Path,
) -> DiscoveryAvailability:
    try:
        loader(path)
    except ValueError:
        return "unavailable"
    return "available"


def _docker_runtime_available() -> bool:
    if shutil.which("docker") is None:
        return False
    return any(
        socket_path.exists() and os.access(socket_path, os.R_OK | os.W_OK)
        for socket_path in (Path("/run/docker.sock"), Path("/var/run/docker.sock"))
    )


def _discovery_unavailable(label: str) -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
        detail=f"{label} discovery is unavailable",
    )
