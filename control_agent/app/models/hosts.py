from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field

from .devices import DeviceProbeConfig, DeviceProbeStatus

HostCategory = Literal[
    "server",
    "desktop",
    "laptop",
    "nas",
    "router",
    "tablet",
    "phone",
    "other",
]


class ManagedHostConfig(BaseModel):
    id: str
    display_name: str
    category: HostCategory
    description: str | None = None
    lan_ip: str | None = None
    tailscale_ip: str | None = None
    tailscale_hostname: str | None = None
    monitoring_api_url: str | None = None
    control_api_url: str | None = None
    enabled: bool = True
    capabilities: list[str] = Field(default_factory=list)
    services: list[str] = Field(default_factory=list)
    tags: list[str] = Field(default_factory=list)
    probes: list[DeviceProbeConfig] = Field(default_factory=list)


class ManagedHostsConfigDocument(BaseModel):
    hosts: list[ManagedHostConfig] = Field(default_factory=list)


class ManagedHostStatus(BaseModel):
    id: str
    display_name: str
    category: HostCategory
    description: str | None = None
    lan_ip: str | None = None
    tailscale_ip: str | None = None
    tailscale_hostname: str | None = None
    monitoring_api_url: str | None = None
    control_api_url: str | None = None
    enabled: bool
    online: bool
    latency_ms: float | None = None
    last_checked: datetime
    last_seen: datetime | None = None
    capabilities: list[str] = Field(default_factory=list)
    services: list[str] = Field(default_factory=list)
    tags: list[str] = Field(default_factory=list)
    probes: list[DeviceProbeStatus] = Field(default_factory=list)
    probe_summary: str


class ManagedHostsResponse(BaseModel):
    hosts: list[ManagedHostStatus]
