from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, status

from ...core.auth import require_bearer_token
from ...core.config import Settings, get_settings
from ...models.devices import DevicesResponse
from ...services.device_probe import load_known_devices, probe_known_devices
from ...services.tailscale_peers import read_tailscale_peers

router = APIRouter(
    prefix="/devices",
    tags=["devices"],
    dependencies=[Depends(require_bearer_token)],
)


@router.get("", response_model=DevicesResponse)
async def get_devices(settings: Settings = Depends(get_settings)) -> DevicesResponse:
    try:
        configs = load_known_devices(settings.known_devices_config_path)
    except ValueError as error:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Known devices configuration is invalid",
        ) from error

    tailscale_peers = read_tailscale_peers()
    return await probe_known_devices(configs, tailscale_peers=tailscale_peers)
