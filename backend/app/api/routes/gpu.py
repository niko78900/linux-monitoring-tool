from __future__ import annotations

from fastapi import APIRouter

from app.models.gpu import GPUResponse
from app.services.gpu_service import get_gpu_metrics

router = APIRouter()


@router.get("/gpu", response_model=GPUResponse)
def gpu_metrics() -> GPUResponse:
    return get_gpu_metrics()
