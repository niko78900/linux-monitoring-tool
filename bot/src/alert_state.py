from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Iterable

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
