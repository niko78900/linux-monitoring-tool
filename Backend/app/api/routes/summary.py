from __future__ import annotations

from fastapi import APIRouter, Depends

from app.core.config import Settings, get_settings
from app.models.summary import SummaryResponse
from app.services.summary_service import get_summary_metrics

router = APIRouter()


@router.get("/summary", response_model=SummaryResponse)
def summary_metrics(settings: Settings = Depends(get_settings)) -> SummaryResponse:
    return get_summary_metrics(settings.disk_mountpoint)
