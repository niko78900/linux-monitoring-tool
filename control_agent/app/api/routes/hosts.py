from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, status

from ...core.auth import require_bearer_token
from ...core.config import Settings, get_settings
from ...models.hosts import ManagedHostStatus, ManagedHostsResponse
from ...services.managed_hosts import load_managed_hosts, probe_managed_hosts
from ...services.tailscale_peers import read_tailscale_peers

router = APIRouter(
    prefix="/hosts",
    tags=["hosts"],
    dependencies=[Depends(require_bearer_token)],
)


@router.get("", response_model=ManagedHostsResponse)
async def get_hosts(settings: Settings = Depends(get_settings)) -> ManagedHostsResponse:
    try:
        configs = load_managed_hosts(settings.managed_hosts_config_path)
    except ValueError as error:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Managed hosts configuration is invalid",
        ) from error

    tailscale_peers = read_tailscale_peers()
    return await probe_managed_hosts(configs, tailscale_peers=tailscale_peers)


@router.get("/{host_id}", response_model=ManagedHostStatus)
async def get_host(
    host_id: str,
    settings: Settings = Depends(get_settings),
) -> ManagedHostStatus:
    response = await get_hosts(settings)
    for host in response.hosts:
        if host.id == host_id:
            return host
    raise HTTPException(
        status_code=status.HTTP_404_NOT_FOUND,
        detail="Managed host not found",
    )
