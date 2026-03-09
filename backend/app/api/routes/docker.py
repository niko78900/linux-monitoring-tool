from __future__ import annotations

from fastapi import APIRouter

from app.models.docker import DockerResponse
from app.services.docker_service import get_docker_metrics

router = APIRouter()


@router.get("/docker", response_model=DockerResponse)
def docker_metrics() -> DockerResponse:
    return get_docker_metrics()
