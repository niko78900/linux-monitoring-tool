from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel

DiscoveryAvailability = Literal["available", "partial", "unavailable", "not_required"]


class ReadOnlyDiscoveryAvailability(BaseModel):
    devices: DiscoveryAvailability
    hosts: DiscoveryAvailability
    services: DiscoveryAvailability
    docker_runtime: DiscoveryAvailability


class DashboardReadHealthResponse(BaseModel):
    status: Literal["ok", "degraded"]
    app_name: str
    version: str
    read_only: Literal[True] = True
    timestamp: datetime
    discovery: ReadOnlyDiscoveryAvailability
