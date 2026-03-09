from __future__ import annotations

from fastapi import APIRouter, Depends

from app.core.config import Settings, get_settings
from app.models.system import SystemResponse
from app.services.system_service import get_system_metrics

router = APIRouter()


@router.get("/system", response_model=SystemResponse)
def system_metrics(settings: Settings = Depends(get_settings)) -> SystemResponse:
    return get_system_metrics(settings.disk_mountpoint)
