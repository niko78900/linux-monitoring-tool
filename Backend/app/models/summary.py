from __future__ import annotations

from pydantic import BaseModel, Field


class SummaryResponse(BaseModel):
    hostname: str
    uptime_human: str
    cpu_percent: float = Field(ge=0)
    memory_percent: float = Field(ge=0)
    disk_percent: float = Field(ge=0)
    gpu_available: bool
    gpu_utilization_percent: float | None = None
    gpu_temp_c: int | None = None
    docker_available: bool
    running_containers: int = Field(ge=0)
