from __future__ import annotations

from datetime import datetime
from typing import Any, Literal

from pydantic import BaseModel, Field

BenchmarkKind = Literal["cpu_single", "cpu_multi", "cpu_stress", "gpu_vkmark"]
BenchmarkState = Literal["idle", "running", "finished", "failed", "stopped"]


class BenchmarkStartRequest(BaseModel):
    kind: str
    duration_seconds: int | None = None
    threads: int | None = None
    workers: int | None = None


class BenchmarkStatusResponse(BaseModel):
    state: BenchmarkState = "idle"
    kind: BenchmarkKind | None = None
    label: str | None = None
    started_at: datetime | None = None
    finished_at: datetime | None = None
    duration_seconds: int | None = None
    threads: int | None = None
    workers: int | None = None
    command: list[str] = Field(default_factory=list)
    return_code: int | None = None
    result: dict[str, Any] = Field(default_factory=dict)
    stdout_tail: list[str] = Field(default_factory=list)
    stderr_tail: list[str] = Field(default_factory=list)
    detail: str | None = None
    nproc: int
    gpu_helper_path: str
    gpu_helper_available: bool
