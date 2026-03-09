from __future__ import annotations

from pydantic import BaseModel


class GPUResponse(BaseModel):
    available: bool
    reason: str | None = None
    name: str | None = None
    temperature_c: int | None = None
    utilization_percent: float | None = None
    memory_total_mb: int | None = None
    memory_used_mb: int | None = None
    memory_free_mb: int | None = None
    power_usage_w: float | None = None
    fan_speed_percent: int | None = None
    driver_version: str | None = None
