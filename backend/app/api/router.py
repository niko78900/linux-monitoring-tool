from __future__ import annotations

from fastapi import APIRouter

from app.api.routes.alerts import router as alerts_router
from app.api.routes.docker import router as docker_router
from app.api.routes.gpu import router as gpu_router
from app.api.routes.health import router as health_router
from app.api.routes.history import router as history_router
from app.api.routes.mobile_alerts import router as mobile_alerts_router
from app.api.routes.summary import router as summary_router
from app.api.routes.system import router as system_router

api_router = APIRouter()
api_router.include_router(health_router, tags=["health"])
api_router.include_router(alerts_router)
api_router.include_router(mobile_alerts_router)
api_router.include_router(history_router, tags=["history"])
api_router.include_router(system_router, tags=["system"])
api_router.include_router(gpu_router, tags=["gpu"])
api_router.include_router(docker_router, tags=["docker"])
api_router.include_router(summary_router, tags=["summary"])
