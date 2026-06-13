from __future__ import annotations

import json
import os
import sqlite3
from contextlib import contextmanager
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Iterable, Iterator

from .models import (
    ActiveAlert,
    AlertCandidate,
    AlertEvent,
    MobileInstallation,
    MobilePushDelivery,
)

SCHEMA_VERSION = 1


class AlertStore:
    def __init__(self, path: Path) -> None:
        self.path = path

    def initialize(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with self._connect() as connection:
            connection.executescript(
                """
                PRAGMA user_version = 1;

                CREATE TABLE IF NOT EXISTS mobile_installations (
                    installation_id TEXT PRIMARY KEY,
                    device_name TEXT NOT NULL,
                    platform TEXT NOT NULL,
                    fcm_token TEXT NOT NULL,
                    enabled INTEGER NOT NULL,
                    include_recovery INTEGER NOT NULL,
                    last_registered_at TEXT NOT NULL,
                    last_test_sent_at TEXT NULL
                );

                CREATE TABLE IF NOT EXISTS alert_state (
                    alert_key TEXT PRIMARY KEY,
                    first_seen_at TEXT NOT NULL,
                    active_since TEXT NULL,
                    last_seen_at TEXT NOT NULL,
                    current_state TEXT NOT NULL,
                    last_payload_json TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS alert_events (
                    event_id INTEGER PRIMARY KEY AUTOINCREMENT,
                    alert_key TEXT NOT NULL,
                    event_type TEXT NOT NULL,
                    category TEXT NOT NULL,
                    severity TEXT NOT NULL,
                    title TEXT NOT NULL,
                    message TEXT NOT NULL,
                    route TEXT NULL,
                    mobile_scope INTEGER NOT NULL,
                    created_at TEXT NOT NULL,
                    recovered_after_seconds INTEGER NULL
                );

                CREATE TABLE IF NOT EXISTS mobile_push_outbox (
                    delivery_id INTEGER PRIMARY KEY AUTOINCREMENT,
                    event_id INTEGER NOT NULL,
                    installation_id TEXT NOT NULL,
                    attempt_count INTEGER NOT NULL,
                    next_attempt_at TEXT NOT NULL,
                    delivered_at TEXT NULL,
                    cancelled_at TEXT NULL,
                    last_error_safe TEXT NULL,
                    UNIQUE(event_id, installation_id),
                    FOREIGN KEY(event_id) REFERENCES alert_events(event_id) ON DELETE CASCADE,
                    FOREIGN KEY(installation_id) REFERENCES mobile_installations(installation_id) ON DELETE CASCADE
                );

                CREATE INDEX IF NOT EXISTS idx_alert_events_created
                    ON alert_events(event_id);
                CREATE INDEX IF NOT EXISTS idx_mobile_outbox_due
                    ON mobile_push_outbox(next_attempt_at, delivered_at, cancelled_at);
                CREATE INDEX IF NOT EXISTS idx_mobile_outbox_event
                    ON mobile_push_outbox(event_id);
                """
            )
        _chmod_if_possible(self.path, 0o600)

    def upsert_installation(
        self,
        *,
        installation_id: str,
        device_name: str,
        platform: str,
        fcm_token: str,
        enabled: bool,
        include_recovery: bool,
        now: datetime | None = None,
    ) -> MobileInstallation:
        current = _utc(now)
        with self._connect() as connection:
            connection.execute(
                """
                INSERT INTO mobile_installations (
                    installation_id,
                    device_name,
                    platform,
                    fcm_token,
                    enabled,
                    include_recovery,
                    last_registered_at,
                    last_test_sent_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, NULL)
                ON CONFLICT(installation_id) DO UPDATE SET
                    device_name=excluded.device_name,
                    platform=excluded.platform,
                    fcm_token=excluded.fcm_token,
                    enabled=excluded.enabled,
                    include_recovery=excluded.include_recovery,
                    last_registered_at=excluded.last_registered_at
                """,
                (
                    installation_id,
                    device_name,
                    platform,
                    fcm_token,
                    int(enabled),
                    int(include_recovery),
                    _iso(current),
                ),
            )
        installation = self.get_installation(installation_id)
        if installation is None:  # pragma: no cover - defensive
            raise RuntimeError("Mobile installation upsert failed.")
        return installation

    def get_installation(self, installation_id: str) -> MobileInstallation | None:
        with self._connect() as connection:
            row = connection.execute(
                """
                SELECT installation_id, device_name, platform, fcm_token, enabled,
                       include_recovery, last_registered_at, last_test_sent_at
                FROM mobile_installations
                WHERE installation_id = ?
                """,
                (installation_id,),
            ).fetchone()
        return _installation_from_row(row) if row is not None else None

    def disable_installation(self, installation_id: str) -> None:
        with self._connect() as connection:
            connection.execute(
                "UPDATE mobile_installations SET enabled = 0 WHERE installation_id = ?",
                (installation_id,),
            )

    def disable_installations(self, installation_ids: Iterable[str]) -> None:
        ids = [item for item in installation_ids if item]
        if not ids:
            return
        with self._connect() as connection:
            connection.executemany(
                "UPDATE mobile_installations SET enabled = 0 WHERE installation_id = ?",
                [(item,) for item in ids],
            )

    def status_for_installation(self, installation_id: str | None) -> MobileInstallation | None:
        if not installation_id:
            return None
        return self.get_installation(installation_id)

    def mark_test_sent(
        self,
        installation_id: str,
        *,
        now: datetime | None = None,
    ) -> None:
        with self._connect() as connection:
            connection.execute(
                "UPDATE mobile_installations SET last_test_sent_at = ? WHERE installation_id = ?",
                (_iso(_utc(now)), installation_id),
            )

    def enabled_installation_count(self) -> int:
        with self._connect() as connection:
            row = connection.execute(
                "SELECT COUNT(*) AS count FROM mobile_installations WHERE enabled = 1"
            ).fetchone()
        return int(row["count"] if row is not None else 0)

    def import_legacy_json(self, path: Path, *, now: datetime | None = None) -> int:
        if not path.exists():
            return 0
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            return 0
        installations = payload.get("installations")
        if not isinstance(installations, list):
            return 0
        imported = 0
        for item in installations:
            if not isinstance(item, dict):
                continue
            installation_id = str(item.get("installation_id") or "").strip()
            device_name = str(item.get("device_name") or "").strip()
            fcm_token = str(item.get("fcm_token") or "").strip()
            platform = str(item.get("platform") or "android").strip()
            if not installation_id or not device_name or not fcm_token or platform != "android":
                continue
            self.upsert_installation(
                installation_id=installation_id,
                device_name=device_name,
                platform=platform,
                fcm_token=fcm_token,
                enabled=bool(item.get("enabled", True)),
                include_recovery=bool(item.get("include_recovery", True)),
                now=now,
            )
            imported += 1
        return imported

    def transition_alerts(
        self,
        candidates: list[AlertCandidate],
        *,
        now: datetime | None = None,
        grace_seconds: int,
        mobile_push_enabled: bool,
        include_recovery: bool,
    ) -> list[AlertEvent]:
        current = _utc(now)
        current_by_key = {candidate.key: candidate for candidate in candidates}
        events: list[AlertEvent] = []
        with self._connect() as connection:
            rows = connection.execute(
                """
                SELECT alert_key, first_seen_at, active_since, last_seen_at,
                       current_state, last_payload_json
                FROM alert_state
                """
            ).fetchall()
            state_by_key = {str(row["alert_key"]): row for row in rows}

            for key, candidate in current_by_key.items():
                row = state_by_key.get(key)
                payload_json = _candidate_json(candidate)
                if row is None:
                    connection.execute(
                        """
                        INSERT INTO alert_state (
                            alert_key, first_seen_at, active_since, last_seen_at,
                            current_state, last_payload_json
                        )
                        VALUES (?, ?, NULL, ?, 'pending', ?)
                        """,
                        (key, _iso(current), _iso(current), payload_json),
                    )
                    first_seen = current
                    current_state = "pending"
                else:
                    first_seen = _parse_time(row["first_seen_at"])
                    current_state = str(row["current_state"])
                    connection.execute(
                        """
                        UPDATE alert_state
                        SET last_seen_at = ?, last_payload_json = ?
                        WHERE alert_key = ?
                        """,
                        (_iso(current), payload_json, key),
                    )

                if current_state == "pending" and (current - first_seen).total_seconds() >= grace_seconds:
                    event = self._insert_event(
                        connection,
                        alert_key=key,
                        event_type="active",
                        category=candidate.category,
                        severity=candidate.severity,
                        title=candidate.title,
                        message=candidate.message,
                        route=candidate.route,
                        mobile_scope=candidate.mobile_scope,
                        created_at=current,
                        recovered_after_seconds=None,
                    )
                    events.append(event)
                    connection.execute(
                        """
                        UPDATE alert_state
                        SET active_since = ?, current_state = 'active'
                        WHERE alert_key = ?
                        """,
                        (_iso(current), key),
                    )
                    if mobile_push_enabled:
                        self._queue_mobile_deliveries(
                            connection,
                            event=event,
                            include_recovery=include_recovery,
                            now=current,
                        )

            stale_rows = [
                row for key, row in state_by_key.items() if key not in current_by_key
            ]
            for row in stale_rows:
                key = str(row["alert_key"])
                if str(row["current_state"]) == "active":
                    payload = _payload_from_json(str(row["last_payload_json"]))
                    active_since = _parse_optional_time(row["active_since"]) or _parse_time(row["first_seen_at"])
                    recovered_after = max(0, int((current - active_since).total_seconds()))
                    self._cancel_pending_active_deliveries(connection, key, now=current)
                    event = self._insert_event(
                        connection,
                        alert_key=key,
                        event_type="recovery",
                        category=str(payload.get("category") or "unknown"),
                        severity="warning",
                        title=_recovery_title(key, str(payload.get("title") or "Alert")),
                        message=_recovery_message(
                            str(payload.get("title") or "Alert"),
                            recovered_after,
                        ),
                        route=_optional_string(payload.get("route")),
                        mobile_scope=bool(payload.get("mobile_scope")),
                        created_at=current,
                        recovered_after_seconds=recovered_after,
                    )
                    events.append(event)
                    if mobile_push_enabled:
                        self._queue_mobile_deliveries(
                            connection,
                            event=event,
                            include_recovery=include_recovery,
                            now=current,
                        )

                connection.execute("DELETE FROM alert_state WHERE alert_key = ?", (key,))

        events.sort(key=lambda event: event.event_id)
        return events

    def active_alerts(self) -> list[ActiveAlert]:
        with self._connect() as connection:
            rows = connection.execute(
                """
                SELECT alert_key, first_seen_at, active_since, last_seen_at, last_payload_json
                FROM alert_state
                WHERE current_state = 'active'
                ORDER BY alert_key
                """
            ).fetchall()
        alerts: list[ActiveAlert] = []
        for row in rows:
            payload = _payload_from_json(str(row["last_payload_json"]))
            alerts.append(
                ActiveAlert(
                    alert_key=str(row["alert_key"]),
                    category=str(payload.get("category") or "unknown"),
                    severity="critical" if payload.get("severity") == "critical" else "warning",
                    title=str(payload.get("title") or "Alert"),
                    message=str(payload.get("message") or ""),
                    first_seen_at=_parse_time(row["first_seen_at"]),
                    active_since=_parse_time(row["active_since"]),
                    last_seen_at=_parse_time(row["last_seen_at"]),
                )
            )
        return alerts

    def list_events(self, *, after_id: int = 0, limit: int = 100) -> list[AlertEvent]:
        bounded_limit = max(1, min(int(limit), 500))
        with self._connect() as connection:
            rows = connection.execute(
                """
                SELECT event_id, alert_key, event_type, category, severity, title,
                       message, route, mobile_scope, created_at, recovered_after_seconds
                FROM alert_events
                WHERE event_id > ?
                ORDER BY event_id ASC
                LIMIT ?
                """,
                (max(0, int(after_id)), bounded_limit),
            ).fetchall()
        return [_event_from_row(row) for row in rows]

    def latest_event_id(self) -> int:
        with self._connect() as connection:
            row = connection.execute(
                "SELECT COALESCE(MAX(event_id), 0) AS latest FROM alert_events"
            ).fetchone()
        return int(row["latest"] if row is not None else 0)

    def pending_mobile_delivery_count(self) -> int:
        with self._connect() as connection:
            row = connection.execute(
                """
                SELECT COUNT(*) AS count
                FROM mobile_push_outbox
                WHERE delivered_at IS NULL AND cancelled_at IS NULL
                """
            ).fetchone()
        return int(row["count"] if row is not None else 0)

    def due_mobile_deliveries(
        self,
        *,
        now: datetime | None = None,
        limit: int = 50,
    ) -> list[MobilePushDelivery]:
        current = _utc(now)
        with self._connect() as connection:
            rows = connection.execute(
                """
                SELECT outbox.delivery_id,
                       outbox.event_id,
                       outbox.attempt_count,
                       events.event_type,
                       events.alert_key,
                       events.title,
                       events.message,
                       events.route,
                       installations.installation_id,
                       installations.fcm_token
                FROM mobile_push_outbox AS outbox
                JOIN alert_events AS events ON events.event_id = outbox.event_id
                JOIN mobile_installations AS installations
                  ON installations.installation_id = outbox.installation_id
                WHERE outbox.delivered_at IS NULL
                  AND outbox.cancelled_at IS NULL
                  AND outbox.next_attempt_at <= ?
                  AND installations.enabled = 1
                ORDER BY outbox.next_attempt_at ASC, outbox.delivery_id ASC
                LIMIT ?
                """,
                (_iso(current), max(1, limit)),
            ).fetchall()
        return [_delivery_from_row(row) for row in rows]

    def mark_delivery_delivered(
        self,
        delivery_id: int,
        *,
        now: datetime | None = None,
    ) -> None:
        with self._connect() as connection:
            connection.execute(
                """
                UPDATE mobile_push_outbox
                SET delivered_at = ?, last_error_safe = NULL
                WHERE delivery_id = ?
                """,
                (_iso(_utc(now)), delivery_id),
            )

    def mark_delivery_cancelled(
        self,
        delivery_id: int,
        *,
        error: str | None = None,
        now: datetime | None = None,
    ) -> None:
        with self._connect() as connection:
            connection.execute(
                """
                UPDATE mobile_push_outbox
                SET cancelled_at = ?, last_error_safe = ?
                WHERE delivery_id = ?
                """,
                (_iso(_utc(now)), _safe_error(error), delivery_id),
            )

    def mark_delivery_retry(
        self,
        delivery_id: int,
        *,
        retry_initial_seconds: int,
        retry_max_seconds: int,
        error: str | None = None,
        now: datetime | None = None,
    ) -> int:
        current = _utc(now)
        with self._connect() as connection:
            row = connection.execute(
                "SELECT attempt_count FROM mobile_push_outbox WHERE delivery_id = ?",
                (delivery_id,),
            ).fetchone()
            if row is None:
                return 0
            next_attempt_count = int(row["attempt_count"]) + 1
            delay = min(
                max(1, retry_initial_seconds) * (2 ** max(0, next_attempt_count - 1)),
                max(1, retry_max_seconds),
            )
            connection.execute(
                """
                UPDATE mobile_push_outbox
                SET attempt_count = ?, next_attempt_at = ?, last_error_safe = ?
                WHERE delivery_id = ?
                """,
                (
                    next_attempt_count,
                    _iso(current + timedelta(seconds=delay)),
                    _safe_error(error),
                    delivery_id,
                ),
            )
        return delay

    def _insert_event(
        self,
        connection: sqlite3.Connection,
        *,
        alert_key: str,
        event_type: str,
        category: str,
        severity: str,
        title: str,
        message: str,
        route: str | None,
        mobile_scope: bool,
        created_at: datetime,
        recovered_after_seconds: int | None,
    ) -> AlertEvent:
        cursor = connection.execute(
            """
            INSERT INTO alert_events (
                alert_key, event_type, category, severity, title, message,
                route, mobile_scope, created_at, recovered_after_seconds
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                alert_key,
                event_type,
                category,
                severity,
                title,
                message,
                route,
                int(mobile_scope),
                _iso(created_at),
                recovered_after_seconds,
            ),
        )
        event_id = int(cursor.lastrowid)
        return AlertEvent(
            event_id=event_id,
            alert_key=alert_key,
            event_type="recovery" if event_type == "recovery" else "active",
            category=category,
            severity="critical" if severity == "critical" else "warning",
            title=title,
            message=message,
            route=route,
            mobile_scope=mobile_scope,
            created_at=created_at,
            recovered_after_seconds=recovered_after_seconds,
        )

    def _queue_mobile_deliveries(
        self,
        connection: sqlite3.Connection,
        *,
        event: AlertEvent,
        include_recovery: bool,
        now: datetime,
    ) -> None:
        if not event.mobile_scope:
            return
        if event.event_type == "recovery" and not include_recovery:
            return
        if event.event_type == "recovery":
            rows = connection.execute(
                """
                SELECT installation_id
                FROM mobile_installations
                WHERE enabled = 1 AND include_recovery = 1
                """
            ).fetchall()
        else:
            rows = connection.execute(
                "SELECT installation_id FROM mobile_installations WHERE enabled = 1"
            ).fetchall()
        connection.executemany(
            """
            INSERT OR IGNORE INTO mobile_push_outbox (
                event_id, installation_id, attempt_count, next_attempt_at
            )
            VALUES (?, ?, 0, ?)
            """,
            [(event.event_id, row["installation_id"], _iso(now)) for row in rows],
        )

    def _cancel_pending_active_deliveries(
        self,
        connection: sqlite3.Connection,
        alert_key: str,
        *,
        now: datetime,
    ) -> None:
        connection.execute(
            """
            UPDATE mobile_push_outbox
            SET cancelled_at = ?, last_error_safe = 'recovered-before-delivery'
            WHERE delivered_at IS NULL
              AND cancelled_at IS NULL
              AND event_id IN (
                SELECT event_id
                FROM alert_events
                WHERE alert_key = ? AND event_type = 'active'
              )
            """,
            (_iso(now), alert_key),
        )

    @contextmanager
    def _connect(self) -> Iterator[sqlite3.Connection]:
        connection = sqlite3.connect(self.path)
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA foreign_keys = ON")
        try:
            yield connection
            connection.commit()
        finally:
            connection.close()


def _candidate_json(candidate: AlertCandidate) -> str:
    return json.dumps(
        {
            "key": candidate.key,
            "category": candidate.category,
            "severity": candidate.severity,
            "title": candidate.title,
            "message": candidate.message,
            "route": candidate.route,
            "mobile_scope": candidate.mobile_scope,
        },
        sort_keys=True,
    )


def _payload_from_json(value: str) -> dict[str, Any]:
    try:
        payload = json.loads(value)
    except json.JSONDecodeError:
        return {}
    return payload if isinstance(payload, dict) else {}


def _installation_from_row(row: sqlite3.Row) -> MobileInstallation:
    return MobileInstallation(
        installation_id=str(row["installation_id"]),
        device_name=str(row["device_name"]),
        platform=str(row["platform"]),
        fcm_token=str(row["fcm_token"]),
        enabled=bool(row["enabled"]),
        include_recovery=bool(row["include_recovery"]),
        last_registered_at=_parse_time(row["last_registered_at"]),
        last_test_sent_at=_parse_optional_time(row["last_test_sent_at"]),
    )


def _event_from_row(row: sqlite3.Row) -> AlertEvent:
    return AlertEvent(
        event_id=int(row["event_id"]),
        alert_key=str(row["alert_key"]),
        event_type="recovery" if row["event_type"] == "recovery" else "active",
        category=str(row["category"]),
        severity="critical" if row["severity"] == "critical" else "warning",
        title=str(row["title"]),
        message=str(row["message"]),
        route=_optional_string(row["route"]),
        mobile_scope=bool(row["mobile_scope"]),
        created_at=_parse_time(row["created_at"]),
        recovered_after_seconds=row["recovered_after_seconds"],
    )


def _delivery_from_row(row: sqlite3.Row) -> MobilePushDelivery:
    return MobilePushDelivery(
        delivery_id=int(row["delivery_id"]),
        event_id=int(row["event_id"]),
        event_type="recovery" if row["event_type"] == "recovery" else "active",
        alert_key=str(row["alert_key"]),
        title=str(row["title"]),
        message=str(row["message"]),
        route=_optional_string(row["route"]),
        installation_id=str(row["installation_id"]),
        fcm_token=str(row["fcm_token"]),
        attempt_count=int(row["attempt_count"]),
    )


def _recovery_title(key: str, fallback_title: str) -> str:
    return {
        "cpu-usage": "CPU usage recovered",
        "gpu-usage": "GPU usage recovered",
        "memory-usage": "Memory usage recovered",
    }.get(key, "Storage recovered" if key.startswith("disk-usage:") else f"{fallback_title} recovered")


def _recovery_message(title: str, recovered_after_seconds: int) -> str:
    minutes = max(1, round(recovered_after_seconds / 60))
    return f"{title} recovered after about {minutes} minute(s)."


def _safe_error(value: str | None) -> str | None:
    if value is None:
        return None
    return value[:240]


def _optional_string(value: object) -> str | None:
    if value is None:
        return None
    text = str(value)
    return text or None


def _utc(value: datetime | None) -> datetime:
    if value is None:
        return datetime.now(timezone.utc)
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


def _iso(value: datetime) -> str:
    return _utc(value).isoformat()


def _parse_time(value: object) -> datetime:
    parsed = _parse_optional_time(value)
    if parsed is None:
        return datetime.now(timezone.utc)
    return parsed


def _parse_optional_time(value: object) -> datetime | None:
    if not isinstance(value, str) or not value:
        return None
    try:
        parsed = datetime.fromisoformat(value)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def _chmod_if_possible(path: Path, mode: int) -> None:
    if os.name == "nt":
        return
    try:
        os.chmod(path, mode)
    except OSError:
        pass
