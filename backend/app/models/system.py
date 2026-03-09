from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field


class PlatformInfo(BaseModel):
    system: str
    release: str
    version: str
    machine: str
    platform: str


class LoadAverage(BaseModel):
    one_min: float
    five_min: float
    fifteen_min: float


class CpuMetrics(BaseModel):
    usage_percent: float = Field(ge=0)
    physical_cores: int = Field(ge=0)
    logical_cores: int = Field(ge=0)
    load_average: LoadAverage | None = None


class MemoryMetrics(BaseModel):
    total: int = Field(ge=0)
    available: int = Field(ge=0)
    used: int = Field(ge=0)
    percent: float = Field(ge=0)


class SwapMetrics(BaseModel):
    total: int = Field(ge=0)
    used: int = Field(ge=0)
    percent: float = Field(ge=0)


class DiskMetrics(BaseModel):
    total: int = Field(ge=0)
    used: int = Field(ge=0)
    free: int = Field(ge=0)
    percent: float = Field(ge=0)
    mountpoint: str


class DiskHealth(BaseModel):
    status: Literal["healthy", "warning", "critical", "unknown"] = "unknown"
    reason: str


class RaidHealth(BaseModel):
    status: Literal["healthy", "warning", "critical", "unknown"] = "unknown"
    reason: str


class DiskDeviceMetrics(BaseModel):
    device: str
    mountpoint: str
    fstype: str
    total: int = Field(ge=0)
    used: int = Field(ge=0)
    free: int = Field(ge=0)
    percent: float = Field(ge=0)
    read_only: bool = False
    available: bool = True
    raid_array: str | None = None
    raid_level: str | None = None
    health: DiskHealth


class RaidArrayMetrics(BaseModel):
    name: str
    device: str
    level: str
    state: str
    raid_disks: int = Field(ge=0)
    active_devices: int = Field(ge=0)
    degraded_devices: int = Field(ge=0)
    sync_action: str | None = None
    members: list[str] = Field(default_factory=list)
    health: RaidHealth


class PhysicalDiskMetrics(BaseModel):
    name: str
    device: str
    model: str | None = None
    vendor: str | None = None
    serial: str | None = None
    size_bytes: int = Field(ge=0)
    rotational: bool | None = None
    removable: bool = False
    state: str | None = None
    mounted_partitions: list[str] = Field(default_factory=list)
    raid_arrays: list[str] = Field(default_factory=list)
    health: DiskHealth


class NetworkMetrics(BaseModel):
    bytes_sent: int = Field(ge=0)
    bytes_recv: int = Field(ge=0)
    packets_sent: int = Field(ge=0)
    packets_recv: int = Field(ge=0)


class SystemResponse(BaseModel):
    hostname: str
    os: PlatformInfo
    kernel_version: str
    uptime_seconds: int = Field(ge=0)
    uptime_human: str
    boot_time: datetime
    cpu: CpuMetrics
    memory: MemoryMetrics
    swap: SwapMetrics
    disk: DiskMetrics
    disks: list[DiskDeviceMetrics] = Field(default_factory=list)
    raid_arrays: list[RaidArrayMetrics] = Field(default_factory=list)
    physical_disks: list[PhysicalDiskMetrics] = Field(default_factory=list)
    network: NetworkMetrics
