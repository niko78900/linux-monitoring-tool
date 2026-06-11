from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field

ServiceAdapter = Literal["docker", "systemd"]
ServiceAction = Literal["start", "stop", "restart"]
HealthProbeType = Literal["http"]


class ServiceHealthProbeConfig(BaseModel):
    type: HealthProbeType
    url: str
    timeout_seconds: int = 3


class ServiceConfig(BaseModel):
    id: str
    display_name: str
    host_id: str
    adapter: ServiceAdapter
    target: str
    allowed_actions: list[ServiceAction] = Field(default_factory=list)
    health_probe: ServiceHealthProbeConfig | None = None


class ServicesConfigDocument(BaseModel):
    services: list[ServiceConfig] = Field(default_factory=list)


class ServiceActionRecord(BaseModel):
    action: ServiceAction
    status: str
    requested_at: datetime
    detail: str | None = None


class ManagedServiceStatus(BaseModel):
    service_id: str
    display_name: str
    host_id: str
    runtime_type: ServiceAdapter
    runtime_state: str
    health_probe_state: str
    last_checked: datetime
    allowed_actions: list[ServiceAction] = Field(default_factory=list)
    last_action: ServiceActionRecord | None = None


class ManagedServicesResponse(BaseModel):
    services: list[ManagedServiceStatus]


class ServiceActionResponse(BaseModel):
    service_id: str
    action: ServiceAction
    status: str
    requested_at: datetime
    detail: str | None = None
