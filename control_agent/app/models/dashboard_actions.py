from __future__ import annotations

import re
from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator

ServiceAction = Literal["start", "stop", "restart"]
ActionName = Literal["start", "stop", "restart", "wake"]
ActionStatus = Literal[
    "queued",
    "running",
    "succeeded",
    "failed",
    "rejected",
    "timed_out",
]
RuntimeKind = Literal["docker_container", "systemd"]
ConfirmationLevel = Literal["normal", "high"]


class ActionRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    confirmed: Literal[True]
    request_id: UUID
    reason: str | None = Field(default=None, max_length=240)

    @field_validator("reason", mode="before")
    @classmethod
    def sanitize_reason(cls, value: object) -> str | None:
        if value is None:
            return None
        if not isinstance(value, str):
            raise ValueError("reason must be text")
        if any(ord(character) < 32 or ord(character) == 127 for character in value):
            raise ValueError("reason contains control characters")
        normalized = re.sub(r"\s+", " ", value).strip()
        return normalized or None


class ActionRecordResponse(BaseModel):
    action_id: UUID
    request_id: UUID
    caller: str
    source_address: str
    target_id: str
    display_name: str
    action: ActionName
    status: ActionStatus
    reason: str | None = None
    requested_at: datetime
    started_at: datetime | None = None
    finished_at: datetime | None = None
    result_summary: str | None = None
    error_code: str | None = None
    duration_ms: int | None = None
    previous_state: str | None = None
    resulting_state: str | None = None


class ActionAcceptedResponse(BaseModel):
    action_id: UUID
    request_id: UUID
    target_id: str
    action: ActionName
    status: ActionStatus
    accepted_at: datetime
    polling_location: str


class ActionHistoryResponse(BaseModel):
    actions: list[ActionRecordResponse]


class ServiceCapability(BaseModel):
    id: str
    name: str
    kind: RuntimeKind
    allowed_actions: list[ServiceAction]
    confirmation_level: ConfirmationLevel
    busy: bool


class ServicesCapabilityResponse(BaseModel):
    services: list[ServiceCapability]


class WakeCapability(BaseModel):
    id: Literal["main-pc"] = "main-pc"
    name: str
    available: bool
    allowed_actions: list[Literal["wake"]] = Field(default_factory=lambda: ["wake"])
    confirmation_level: ConfirmationLevel


class CapabilitiesResponse(BaseModel):
    services: list[ServiceCapability]
    wake_main_pc: WakeCapability | None


class ActionHealthResponse(BaseModel):
    status: Literal["ok", "degraded"]
    app_name: str
    version: str
    action_service_available: bool
    registry_loaded: bool
    registry_service_count: int
    wake_available: bool
    action_database_healthy: bool
    workers_healthy: bool
    timestamp: datetime
