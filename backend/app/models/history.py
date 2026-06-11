from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field

HistoryRange = Literal["1h", "24h", "7d", "30d"]


class HistoryRangeOption(BaseModel):
    key: HistoryRange
    label: str
    duration_seconds: int = Field(ge=1)


class HistoryRangesResponse(BaseModel):
    default_range: HistoryRange
    max_points_cap: int = Field(ge=1)
    ranges: list[HistoryRangeOption]


class OverviewHistoryPoint(BaseModel):
    timestamp: datetime
    cpu_percent_avg: float | None = None
    cpu_percent_max: float | None = None
    cpu_temperature_c_avg: float | None = None
    cpu_temperature_c_max: float | None = None
    memory_percent_avg: float | None = None
    swap_percent_avg: float | None = None
    gpu_utilization_percent_avg: float | None = None
    gpu_temperature_c_avg: float | None = None
    gpu_memory_used_mb_avg: float | None = None
    gpu_power_usage_w_avg: float | None = None
    network_recv_bytes_per_second_avg: float | None = None
    network_send_bytes_per_second_avg: float | None = None
    running_containers_avg: float | None = None


class OverviewHistoryResponse(BaseModel):
    range: HistoryRange
    from_timestamp: datetime = Field(alias="from")
    to_timestamp: datetime = Field(alias="to")
    resolution_seconds: int = Field(ge=1)
    max_points: int = Field(ge=1)
    points: list[OverviewHistoryPoint]


class StorageHistoryPoint(BaseModel):
    timestamp: datetime
    used_bytes_avg: float | None = None
    free_bytes_avg: float | None = None
    total_bytes_avg: float | None = None
    percent_avg: float | None = None
    percent_max: float | None = None
    read_only_any: bool = False
    available_any: bool = False
    health_status: str = "unknown"


class StorageHistoryResponse(BaseModel):
    range: HistoryRange
    mountpoint: str
    from_timestamp: datetime = Field(alias="from")
    to_timestamp: datetime = Field(alias="to")
    resolution_seconds: int = Field(ge=1)
    max_points: int = Field(ge=1)
    points: list[StorageHistoryPoint]


class DiskHistoryPoint(BaseModel):
    timestamp: datetime
    temperature_c_avg: float | None = None
    health_status: str = "unknown"
    kernel_state: str | None = None


class DiskHistoryResponse(BaseModel):
    range: HistoryRange
    device: str
    from_timestamp: datetime = Field(alias="from")
    to_timestamp: datetime = Field(alias="to")
    resolution_seconds: int = Field(ge=1)
    max_points: int = Field(ge=1)
    points: list[DiskHistoryPoint]


class RaidHistoryPoint(BaseModel):
    timestamp: datetime
    active_devices_avg: float | None = None
    degraded_devices_avg: float | None = None
    state: str | None = None
    sync_action: str | None = None
    health_status: str = "unknown"


class RaidHistoryResponse(BaseModel):
    range: HistoryRange
    array_name: str
    from_timestamp: datetime = Field(alias="from")
    to_timestamp: datetime = Field(alias="to")
    resolution_seconds: int = Field(ge=1)
    max_points: int = Field(ge=1)
    points: list[RaidHistoryPoint]
