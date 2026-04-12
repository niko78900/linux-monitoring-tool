from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any, Iterable, Mapping

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
    notified: bool


class AlertState:
    def __init__(
        self,
        *,
        default_notify_after_seconds: int = 0,
        notify_after_by_key: Mapping[str, int] | None = None,
        notify_after_by_prefix: Mapping[str, int] | None = None,
    ) -> None:
        self._active_by_key: dict[str, _ActiveAlertRecord] = {}
        self._default_notify_after_seconds = _normalize_non_negative_int(default_notify_after_seconds)
        self._notify_after_by_key = {
            str(key): _normalize_non_negative_int(value)
            for key, value in (notify_after_by_key or {}).items()
        }
        self._notify_after_by_prefix = {
            str(prefix): _normalize_non_negative_int(value)
            for prefix, value in (notify_after_by_prefix or {}).items()
            if str(prefix)
        }

    def transition(self, current_alerts: Iterable[Alert]) -> tuple[list[Alert], list[RecoveryNotice]]:
        now = datetime.now(timezone.utc)
        current_by_key: dict[str, Alert] = {}
        for alert in current_alerts:
            current_by_key[alert.key] = alert

        new_alerts: list[Alert] = []
        for key, alert in current_by_key.items():
            record = self._active_by_key.get(key)
            if record is None:
                record = _ActiveAlertRecord(
                    alert=alert,
                    first_seen=now,
                    last_seen=now,
                    notified=False,
                )
                self._active_by_key[key] = record
            else:
                record.alert = alert
                record.last_seen = now

            if not record.notified:
                notify_after_seconds = self._notify_after_seconds_for_key(key)
                active_for_seconds = (now - record.first_seen).total_seconds()
                if active_for_seconds >= notify_after_seconds:
                    new_alerts.append(record.alert)
                    record.notified = True

        recoveries: list[RecoveryNotice] = []
        stale_keys = [key for key in self._active_by_key if key not in current_by_key]
        for key in stale_keys:
            record = self._active_by_key.pop(key)
            if not record.notified:
                continue
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
                    "notified": record.notified,
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
            notified = _parse_bool(item.get("notified"), default=True)

            typed_severity = "critical" if severity == "critical" else "warning"
            alert = Alert(key=key, title=title, message=message, severity=typed_severity)
            self._active_by_key[key] = _ActiveAlertRecord(
                alert=alert,
                first_seen=first_seen,
                last_seen=last_seen,
                notified=notified,
            )

    def _notify_after_seconds_for_key(self, key: str) -> int:
        key_delay = self._notify_after_by_key.get(key)
        if key_delay is not None:
            return key_delay

        matched_delay: int | None = None
        matched_prefix_len = -1
        for prefix, delay in self._notify_after_by_prefix.items():
            if key.startswith(prefix) and len(prefix) > matched_prefix_len:
                matched_prefix_len = len(prefix)
                matched_delay = delay
        if matched_delay is not None:
            return matched_delay

        return self._default_notify_after_seconds


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


def _parse_bool(raw_value: object, *, default: bool) -> bool:
    if raw_value is None:
        return default
    if isinstance(raw_value, bool):
        return raw_value
    if isinstance(raw_value, str):
        normalized = raw_value.strip().lower()
        if normalized in {"1", "true", "yes", "on"}:
            return True
        if normalized in {"0", "false", "no", "off"}:
            return False
        return default
    return bool(raw_value)


def _normalize_non_negative_int(raw_value: int) -> int:
    return max(0, int(raw_value))
