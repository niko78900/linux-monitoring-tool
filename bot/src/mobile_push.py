from __future__ import annotations

import asyncio
import json
import logging
import os
import sys
import tempfile
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Iterable

from alert_rules import Alert
from alert_state import RecoveryNotice
from config import BotConfig

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from shared.mobile_push_registry import (  # noqa: E402
    LockedMobilePushRegistry,
    MobilePushInstallation,
    MobilePushRegistryFormatError,
)

logger = logging.getLogger("linux_monitoring.bot")


class MobilePushRegistry(LockedMobilePushRegistry):
    pass


@dataclass(frozen=True)
class MobilePushResult:
    sent_count: int
    failed_count: int = 0
    invalid_installation_ids: tuple[str, ...] = ()
    sent_installation_ids: tuple[str, ...] = ()


@dataclass
class MobilePushOutboxEntry:
    delivery_id: str
    kind: str
    alert_key: str
    title: str
    body: str
    route: str
    attempts: int = 0
    next_attempt_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
    delivered_at: datetime | None = None
    delivered_installation_ids: set[str] = field(default_factory=set)

    @classmethod
    def from_json(cls, payload: dict[str, Any]) -> MobilePushOutboxEntry | None:
        delivery_id = str(payload.get("delivery_id") or "").strip()
        kind = str(payload.get("kind") or "").strip()
        alert_key = str(payload.get("alert_key") or "").strip()
        title = str(payload.get("title") or "").strip()
        body = str(payload.get("body") or "").strip()
        route = str(payload.get("route") or "").strip()
        if not delivery_id or kind not in {"active", "recovery"} or not alert_key:
            return None
        return cls(
            delivery_id=delivery_id,
            kind=kind,
            alert_key=alert_key,
            title=title,
            body=body,
            route=route,
            attempts=_int(payload.get("attempts")),
            next_attempt_at=_datetime(payload.get("next_attempt_at"))
            or datetime.now(timezone.utc),
            delivered_at=_datetime(payload.get("delivered_at")),
            delivered_installation_ids={
                str(item)
                for item in payload.get("delivered_installation_ids", [])
                if str(item)
            },
        )

    def to_json(self) -> dict[str, Any]:
        return {
            "delivery_id": self.delivery_id,
            "kind": self.kind,
            "alert_key": self.alert_key,
            "title": self.title,
            "body": self.body,
            "route": self.route,
            "attempts": self.attempts,
            "next_attempt_at": self.next_attempt_at.isoformat(),
            "delivered_at": self.delivered_at.isoformat()
            if self.delivered_at
            else None,
            "delivered_installation_ids": sorted(self.delivered_installation_ids),
        }


class MobilePushDeliveryOutbox:
    def __init__(
        self,
        path: Path,
        *,
        retry_initial_seconds: int = 30,
        retry_max_seconds: int = 900,
    ) -> None:
        self.path = path
        self.retry_initial_seconds = max(0, retry_initial_seconds)
        self.retry_max_seconds = max(self.retry_initial_seconds, retry_max_seconds)

    def enqueue(self, entry: MobilePushOutboxEntry) -> None:
        entries = self._load()
        current = entries.get(entry.delivery_id)
        if current is None or current.delivered_at is not None:
            entries[entry.delivery_id] = entry
            self._save(entries)

    def due_entries(self, now: datetime | None = None) -> list[MobilePushOutboxEntry]:
        current = now or datetime.now(timezone.utc)
        entries = self._load()
        return [
            entry
            for entry in entries.values()
            if entry.delivered_at is None and entry.next_attempt_at <= current
        ]

    def mark_delivered(
        self,
        delivery_id: str,
        delivered_installation_ids: Iterable[str],
    ) -> None:
        entries = self._load()
        entry = entries.get(delivery_id)
        if entry is None:
            return
        entry.delivered_installation_ids.update(delivered_installation_ids)
        entry.delivered_at = datetime.now(timezone.utc)
        entries[delivery_id] = entry
        self._save(entries)

    def mark_retry(
        self,
        delivery_id: str,
        delivered_installation_ids: Iterable[str] = (),
    ) -> int:
        entries = self._load()
        entry = entries.get(delivery_id)
        if entry is None:
            return 0
        entry.delivered_installation_ids.update(delivered_installation_ids)
        entry.attempts += 1
        delay = min(
            self.retry_initial_seconds * (2 ** max(0, entry.attempts - 1)),
            self.retry_max_seconds,
        )
        entry.next_attempt_at = datetime.now(timezone.utc) + timedelta(seconds=delay)
        entries[delivery_id] = entry
        self._save(entries)
        return delay

    def pending_count(self) -> int:
        return sum(1 for entry in self._load().values() if entry.delivered_at is None)

    def _load(self) -> dict[str, MobilePushOutboxEntry]:
        if not self.path.exists():
            return {}
        try:
            payload = json.loads(self.path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            logger.warning("Mobile push outbox is unreadable or malformed: %s", self.path)
            return {}
        raw_entries = payload.get("deliveries")
        if not isinstance(raw_entries, list):
            return {}
        entries: dict[str, MobilePushOutboxEntry] = {}
        for raw in raw_entries:
            if not isinstance(raw, dict):
                continue
            entry = MobilePushOutboxEntry.from_json(raw)
            if entry is not None:
                entries[entry.delivery_id] = entry
        return entries

    def _save(self, entries: dict[str, MobilePushOutboxEntry]) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        payload = {
            "deliveries": [
                entry.to_json()
                for entry in sorted(entries.values(), key=lambda item: item.delivery_id)
            ]
        }
        target_gid = _target_gid(self.path)
        fd, temp_name = tempfile.mkstemp(
            prefix=f".{self.path.name}.",
            suffix=".tmp",
            dir=str(self.path.parent),
            text=True,
        )
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                json.dump(payload, handle, indent=2, sort_keys=True)
                handle.write("\n")
            _chmod_if_possible(Path(temp_name), 0o640)
            _chown_gid_if_possible(Path(temp_name), target_gid)
            _replace_state_file(temp_name, self.path)
            _chmod_if_possible(self.path, 0o640)
            _chown_gid_if_possible(self.path, target_gid)
        finally:
            if os.path.exists(temp_name):
                os.unlink(temp_name)


class FirebaseMobilePushSender:
    def __init__(self, service_account_file: Path) -> None:
        self.service_account_file = service_account_file

    def send(
        self,
        *,
        installations: list[MobilePushInstallation],
        title: str,
        body: str,
        route: str,
        alert_key: str,
    ) -> MobilePushResult:
        if not installations:
            return MobilePushResult(sent_count=0)
        if not self.service_account_file.exists():
            return MobilePushResult(sent_count=0, failed_count=len(installations))

        import firebase_admin
        from firebase_admin import credentials, messaging

        if not firebase_admin._apps:
            credential = credentials.Certificate(str(self.service_account_file))
            firebase_admin.initialize_app(credential)

        messages = [
            messaging.Message(
                token=installation.fcm_token,
                notification=messaging.Notification(title=title, body=body),
                android=messaging.AndroidConfig(
                    priority="high",
                    notification=messaging.AndroidNotification(
                        channel_id="homelab_urgent_alerts_v1",
                        priority="high",
                        visibility="private",
                        icon="ic_homelab_notification",
                        default_sound=True,
                        default_vibrate_timings=True,
                    ),
                ),
                data={
                    "alert_key": alert_key,
                    "route": route,
                    "title": title,
                    "body": body,
                },
            )
            for installation in installations
        ]
        response = messaging.send_each(messages)
        invalid_ids: list[str] = []
        sent_ids: list[str] = []
        for installation, result in zip(installations, response.responses):
            if result.success:
                sent_ids.append(installation.installation_id)
                continue
            code = getattr(getattr(result, "exception", None), "code", "")
            if code in {
                "registration-token-not-registered",
                "invalid-registration-token",
            }:
                invalid_ids.append(installation.installation_id)
        return MobilePushResult(
            sent_count=response.success_count,
            failed_count=response.failure_count,
            invalid_installation_ids=tuple(invalid_ids),
            sent_installation_ids=tuple(sent_ids),
        )


class MobilePushDispatcher:
    def __init__(
        self,
        *,
        enabled: bool,
        include_recovery: bool,
        registry: MobilePushRegistry,
        sender: FirebaseMobilePushSender,
        outbox: MobilePushDeliveryOutbox,
    ) -> None:
        self.enabled = enabled
        self.include_recovery = include_recovery
        self.registry = registry
        self.sender = sender
        self.outbox = outbox

    @classmethod
    def from_config(cls, config: BotConfig) -> MobilePushDispatcher:
        return cls(
            enabled=config.mobile_push_enabled,
            include_recovery=config.mobile_push_include_recovery,
            registry=MobilePushRegistry(Path(config.mobile_push_token_registry_file)),
            sender=FirebaseMobilePushSender(Path(config.firebase_service_account_file)),
            outbox=MobilePushDeliveryOutbox(
                Path(config.mobile_push_outbox_file),
                retry_initial_seconds=config.mobile_push_retry_initial_seconds,
                retry_max_seconds=config.mobile_push_retry_max_seconds,
            ),
        )

    async def dispatch(
        self,
        *,
        alerts: list[Alert],
        recoveries: list[RecoveryNotice],
    ) -> None:
        if not self.enabled:
            return
        for alert in alerts:
            if _is_mobile_alert_key(alert.key):
                title, body, route = _format_mobile_alert(alert)
                self.outbox.enqueue(
                    MobilePushOutboxEntry(
                        delivery_id=f"active:{alert.key}",
                        kind="active",
                        alert_key=alert.key,
                        title=title,
                        body=body,
                        route=route,
                    )
                )
        if self.include_recovery:
            for recovery in recoveries:
                if _is_mobile_alert_key(recovery.key):
                    title, body, route = _format_mobile_recovery(recovery)
                    self.outbox.enqueue(
                        MobilePushOutboxEntry(
                            delivery_id=f"recovery:{recovery.key}",
                            kind="recovery",
                            alert_key=recovery.key,
                            title=title,
                            body=body,
                            route=route,
                        )
                    )

        try:
            installations = self.registry.enabled_installations()
        except MobilePushRegistryFormatError as error:
            logger.warning("Mobile push registry unavailable: %s", error)
            return
        if not installations:
            return
        for entry in self.outbox.due_entries():
            if entry.kind == "recovery" and not self.include_recovery:
                self.outbox.mark_delivered(
                    entry.delivery_id,
                    entry.delivered_installation_ids,
                )
                continue
            await self._send_entry(entry, installations)

    async def _send_entry(
        self,
        entry: MobilePushOutboxEntry,
        installations: list[MobilePushInstallation],
    ) -> None:
        eligible = [
            installation
            for installation in installations
            if installation.installation_id not in entry.delivered_installation_ids
            and (entry.kind != "recovery" or installation.include_recovery)
        ]
        if not eligible:
            self.outbox.mark_delivered(entry.delivery_id, entry.delivered_installation_ids)
            return
        try:
            result = await asyncio.to_thread(
                self.sender.send,
                installations=eligible,
                title=entry.title,
                body=entry.body,
                route=entry.route,
                alert_key=entry.alert_key,
            )
        except Exception:
            delay = self.outbox.mark_retry(entry.delivery_id)
            logger.exception(
                "Mobile push send failed for delivery=%s retry_in=%ss",
                entry.delivery_id,
                delay,
            )
            return

        if result.invalid_installation_ids:
            self.registry.disable_installations(set(result.invalid_installation_ids))
        delivered_ids = set(result.sent_installation_ids)
        if not delivered_ids and result.sent_count == len(eligible):
            delivered_ids = {installation.installation_id for installation in eligible}
        remaining = {
            installation.installation_id
            for installation in eligible
            if installation.installation_id not in delivered_ids
            and installation.installation_id not in result.invalid_installation_ids
        }
        if remaining or result.failed_count:
            delay = self.outbox.mark_retry(entry.delivery_id, delivered_ids)
            logger.warning(
                "Mobile push delivery=%s sent=%s failed=%s invalid=%s retry_in=%ss",
                entry.delivery_id,
                result.sent_count,
                result.failed_count,
                len(result.invalid_installation_ids),
                delay,
            )
            return
        self.outbox.mark_delivered(entry.delivery_id, delivered_ids)
        logger.info(
            "Mobile push delivery=%s sent=%s invalid=%s",
            entry.delivery_id,
            result.sent_count,
            len(result.invalid_installation_ids),
        )


def _is_mobile_alert_key(key: str) -> bool:
    return key in {"cpu-usage", "gpu-usage", "memory-usage"} or key.startswith(
        "disk-usage:"
    )


def _route_for_key(key: str) -> str:
    if key == "gpu-usage":
        return "/gpu"
    if key.startswith("disk-usage:"):
        return "/storage"
    return "/overview"


def _format_mobile_alert(alert: Alert) -> tuple[str, str, str]:
    title = {
        "cpu-usage": "High CPU usage",
        "gpu-usage": "High GPU usage",
        "memory-usage": "High RAM usage",
    }.get(alert.key, "Low storage space")
    return title, _friendly_storage_text(alert.message), _route_for_key(alert.key)


def _format_mobile_recovery(recovery: RecoveryNotice) -> tuple[str, str, str]:
    title = {
        "cpu-usage": "CPU usage recovered",
        "gpu-usage": "GPU usage recovered",
        "memory-usage": "RAM usage recovered",
    }.get(recovery.key, "Storage recovered")
    minutes = max(1, round(recovery.was_active_for_seconds / 60))
    body = f"{_friendly_storage_text(recovery.title)} recovered after about {minutes} minute(s)."
    return title, body, _route_for_key(recovery.key)


def _friendly_storage_text(value: str) -> str:
    return (
        value.replace("/mnt/warm", "Warm Storage")
        .replace("/mnt/storage", "Cold Storage")
        .replace("/mnt/", "")
    )


def _target_gid(path: Path) -> int | None:
    if os.name == "nt":
        return None
    try:
        if path.exists():
            return path.stat().st_gid
        return path.parent.stat().st_gid
    except OSError:
        return None


def _chmod_if_possible(path: Path, mode: int) -> None:
    if os.name == "nt":
        return
    try:
        os.chmod(path, mode)
    except OSError:
        pass


def _chown_gid_if_possible(path: Path, gid: int | None) -> None:
    if os.name == "nt" or gid is None:
        return
    try:
        os.chown(path, -1, gid)
    except OSError:
        pass


def _replace_state_file(source: str | Path, target: Path) -> None:
    try:
        os.replace(source, target)
    except PermissionError:
        if os.name != "nt":
            raise
        target.unlink(missing_ok=True)
        os.replace(source, target)


def _datetime(value: object) -> datetime | None:
    if not isinstance(value, str):
        return None
    try:
        parsed = datetime.fromisoformat(value)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def _int(value: object) -> int:
    try:
        return max(0, int(value))
    except (TypeError, ValueError):
        return 0
