from __future__ import annotations

from fastapi import APIRouter

from .routes import actions, devices, health, neighbors

api_router = APIRouter()
api_router.include_router(health.router)
api_router.include_router(actions.router)
api_router.include_router(devices.router)
api_router.include_router(neighbors.router)
