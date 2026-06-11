from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field

DeviceCategory = Literal["server", "desktop", "laptop", "tablet", "phone", "router", "other"]
ProbeType = Literal["tcp", "ping"]


class DeviceProbeConfig(BaseModel):
    type: ProbeType
    label: str
    port: int | None = None


class KnownDeviceConfig(BaseModel):
    id: str
    name: str
    category: DeviceCategory
    lan_ip: str | None = None
    tailscale_ip: str | None = None
    wol_enabled: bool = False
    wake_action: str | None = None
    notes: str | None = None
    probes: list[DeviceProbeConfig] = Field(default_factory=list)


class KnownDevicesConfigDocument(BaseModel):
    devices: list[KnownDeviceConfig] = Field(default_factory=list)


class DeviceProbeStatus(BaseModel):
    type: ProbeType
    label: str
    port: int | None = None
    reachable: bool
    latency_ms: float | None = None
    summary: str


class KnownDeviceStatus(BaseModel):
    id: str
    name: str
    category: DeviceCategory
    lan_ip: str | None = None
    tailscale_ip: str | None = None
    online: bool
    latency_ms: float | None = None
    last_checked: datetime
    last_seen: datetime | None = None
    wol_enabled: bool
    wake_action: str | None = None
    notes: str | None = None
    probes: list[DeviceProbeStatus] = Field(default_factory=list)
    probe_summary: str


class DevicesResponse(BaseModel):
    devices: list[KnownDeviceStatus]
