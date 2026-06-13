from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from typing import Literal

AlertSeverity = Literal["warning", "critical"]
AlertEventType = Literal["active", "recovery"]


@dataclass(frozen=True)
class AlertCandidate:
    key: str
    category: str
    severity: AlertSeverity
    title: str
    message: str
    route: str | None = None
    mobile_scope: bool = False


@dataclass(frozen=True)
class MobileInstallation:
    installation_id: str
    device_name: str
    platform: str
    fcm_token: str
    enabled: bool
    include_recovery: bool
    last_registered_at: datetime
    last_test_sent_at: datetime | None = None


@dataclass(frozen=True)
class AlertEvent:
    event_id: int
    alert_key: str
    event_type: AlertEventType
    category: str
    severity: AlertSeverity
    title: str
    message: str
    route: str | None
    mobile_scope: bool
    created_at: datetime
    recovered_after_seconds: int | None = None


@dataclass(frozen=True)
class ActiveAlert:
    alert_key: str
    category: str
    severity: AlertSeverity
    title: str
    message: str
    first_seen_at: datetime
    active_since: datetime
    last_seen_at: datetime


@dataclass(frozen=True)
class MobilePushDelivery:
    delivery_id: int
    event_id: int
    event_type: AlertEventType
    alert_key: str
    title: str
    message: str
    route: str | None
    installation_id: str
    fcm_token: str
    attempt_count: int


@dataclass(frozen=True)
class MobilePushResult:
    sent_count: int
    invalid_token: bool = False
    safe_error: str | None = None
