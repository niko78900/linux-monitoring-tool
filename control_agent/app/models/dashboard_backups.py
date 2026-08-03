from __future__ import annotations

from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator

BackupJobStatus = Literal[
    "queued",
    "preparing",
    "running",
    "verifying",
    "succeeded",
    "failed",
    "cancel_requested",
    "cancelled",
    "timed_out",
    "rejected",
]


class BackupStartRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    confirmed: Literal[True]
    request_id: UUID
    reason: str | None = Field(default=None, max_length=240)

    @field_validator("reason")
    @classmethod
    def sanitize_reason(cls, value: str | None) -> str | None:
        if value is None:
            return None
        if any(ord(character) < 32 or ord(character) == 127 for character in value):
            raise ValueError("reason contains control characters")
        normalized = " ".join(value.split())
        if not normalized:
            return None
        if len(normalized) > 240:
            raise ValueError("reason is too long")
        return normalized


class BackupJobResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    job_id: UUID
    request_id: UUID
    plan_id: str
    display_name: str
    status: BackupJobStatus
    reason: str | None = None
    requested_at: datetime
    started_at: datetime | None = None
    finished_at: datetime | None = None
    current_phase: str
    progress_percent: float | None = None
    files_examined: int | None = None
    files_copied: int | None = None
    bytes_examined: int | None = None
    bytes_copied: int | None = None
    source_size_estimate: int | None = None
    destination_snapshot: str | None = None
    duration_ms: int | None = None
    verification_state: Literal["pending", "passed", "failed", "not_applicable"]
    manifest_path: str | None = None
    result_summary: str | None = None
    error_code: str | None = None
    cancellation_requested: bool


class BackupAcceptedResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    job: BackupJobResponse
    duplicate: bool
    polling_location: str


class BackupJobHistoryResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    jobs: list[BackupJobResponse]


class BackupPlanResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: str
    display_name: str
    description: str
    enabled: bool
    estimated_source_size: int
    last_successful_run: datetime | None = None
    allowed_to_start_now: bool
    blocking_reason: str | None = None
    destination_free_bytes: int | None = None
    retention_policy: str
    confirmation_level: Literal["high"]


class BackupPlanListResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    plans: list[BackupPlanResponse]


class BackupHealthResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    status: Literal["ok", "degraded"]
    version: str
    registry_loaded: bool
    plan_count: int
    database_healthy: bool
    worker_healthy: bool
    cold_storage_mounted: bool
    cold_storage_writable: bool
    raid_healthy: bool
    free_bytes: int | None = None
    running_job_count: int
    observation_timestamp: datetime


class BackupErrorResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    detail: str
    error_code: str
    job_id: UUID | None = None
