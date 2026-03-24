from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any, Iterable

from alert_rules import Alert


@dataclass(frozen=True)
class RecoveryNotice:
    key: str
    title: str
    message: str
    was_active_for_seconds: int


@dataclass
class _ActiveAlertRecord:
    alert: Alert
    first_seen: datetime
    last_seen: datetime


class AlertState:
    def __init__(self) -> None:
        self._active_by_key: dict[str, _ActiveAlertRecord] = {}

    def transition(self, current_alerts: Iterable[Alert]) -> tuple[list[Alert], list[RecoveryNotice]]:
        now = datetime.now(timezone.utc)
        current_by_key: dict[str, Alert] = {}
        for alert in current_alerts:
            current_by_key[alert.key] = alert

        new_alerts: list[Alert] = []
        for key, alert in current_by_key.items():
            record = self._active_by_key.get(key)
            if record is None:
                new_alerts.append(alert)
                self._active_by_key[key] = _ActiveAlertRecord(alert=alert, first_seen=now, last_seen=now)
                continue

            record.alert = alert
            record.last_seen = now

        recoveries: list[RecoveryNotice] = []
        stale_keys = [key for key in self._active_by_key if key not in current_by_key]
        for key in stale_keys:
            record = self._active_by_key.pop(key)
            active_seconds = max(0, int((now - record.first_seen).total_seconds()))
            recoveries.append(
                RecoveryNotice(
                    key=key,
                    title=record.alert.title,
                    message=f"{record.alert.title} recovered.",
                    was_active_for_seconds=active_seconds,
                )
            )

        new_alerts.sort(key=lambda alert: alert.key)
        recoveries.sort(key=lambda recovery: recovery.key)
        return new_alerts, recoveries

    @property
    def active_count(self) -> int:
        return len(self._active_by_key)

    def to_snapshot(self) -> dict[str, Any]:
        active: list[dict[str, Any]] = []
        for key, record in self._active_by_key.items():
            active.append(
                {
                    "key": key,
                    "title": record.alert.title,
                    "message": record.alert.message,
                    "severity": record.alert.severity,
                    "first_seen": record.first_seen.isoformat(),
                    "last_seen": record.last_seen.isoformat(),
                }
            )
        return {"active": active}

    def load_snapshot(self, payload: dict[str, Any]) -> None:
        self._active_by_key = {}
        active_payload = payload.get("active")
        if not isinstance(active_payload, list):
            return

        for item in active_payload:
            if not isinstance(item, dict):
                continue

            key = str(item.get("key") or "").strip()
            title = str(item.get("title") or "").strip()
            message = str(item.get("message") or "").strip()
            severity = str(item.get("severity") or "").strip().lower()
            if not key or not title or severity not in {"warning", "critical"}:
                continue

            first_seen = _parse_iso_datetime(item.get("first_seen")) or datetime.now(timezone.utc)
            last_seen = _parse_iso_datetime(item.get("last_seen")) or first_seen

            typed_severity = "critical" if severity == "critical" else "warning"
            alert = Alert(key=key, title=title, message=message, severity=typed_severity)
            self._active_by_key[key] = _ActiveAlertRecord(alert=alert, first_seen=first_seen, last_seen=last_seen)


def _parse_iso_datetime(raw_value: object) -> datetime | None:
    if not isinstance(raw_value, str):
        return None
    try:
        parsed = datetime.fromisoformat(raw_value)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)
