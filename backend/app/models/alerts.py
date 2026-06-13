from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, Field


class AlertEventResponse(BaseModel):
    event_id: int
    alert_key: str
    event_type: str
    category: str
    severity: str
    title: str
    message: str
    route: str | None = None
    created_at: datetime
    recovered_after_seconds: int | None = Field(default=None, ge=0)


class AlertEventsResponse(BaseModel):
    events: list[AlertEventResponse]
    latest_event_id: int


class ActiveAlertResponse(BaseModel):
    alert_key: str
    category: str
    severity: str
    title: str
    message: str
    first_seen_at: datetime
    active_since: datetime
    last_seen_at: datetime


class ActiveAlertsResponse(BaseModel):
    alerts: list[ActiveAlertResponse]


class AlertStatusResponse(BaseModel):
    alerts_enabled: bool
    alert_monitor_running: bool
    firebase_configured: bool
    enabled_installation_count: int
    pending_mobile_delivery_count: int
    latest_event_id: int
