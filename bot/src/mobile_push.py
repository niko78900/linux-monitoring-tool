from __future__ import annotations

import json
import logging
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Iterable

from alert_rules import Alert
from alert_state import RecoveryNotice
from config import BotConfig

logger = logging.getLogger("linux_monitoring.bot")


@dataclass(frozen=True)
class MobilePushInstallation:
    installation_id: str
    fcm_token: str
    enabled: bool


@dataclass(frozen=True)
class MobilePushResult:
    sent_count: int
    failed_count: int = 0
    invalid_installation_ids: tuple[str, ...] = ()


class MobilePushRegistry:
    def __init__(self, path: Path) -> None:
        self.path = path

    def enabled_installations(self) -> list[MobilePushInstallation]:
        if not self.path.exists():
            return []
        try:
            payload = json.loads(self.path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            return []
        records = payload.get("installations")
        if not isinstance(records, list):
            return []
        installations: list[MobilePushInstallation] = []
        for record in records:
            if not isinstance(record, dict):
                continue
            installation_id = str(record.get("installation_id") or "").strip()
            token = str(record.get("fcm_token") or "").strip()
            enabled = bool(record.get("enabled", True))
            if installation_id and token and enabled:
                installations.append(
                    MobilePushInstallation(
                        installation_id=installation_id,
                        fcm_token=token,
                        enabled=enabled,
                    )
                )
        return installations

    def disable_installations(self, installation_ids: Iterable[str]) -> None:
        ids = {item for item in installation_ids if item}
        if not ids or not self.path.exists():
            return
        try:
            payload = json.loads(self.path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            return
        records = payload.get("installations")
        if not isinstance(records, list):
            return
        changed = False
        for record in records:
            if isinstance(record, dict) and record.get("installation_id") in ids:
                record["enabled"] = False
                changed = True
        if not changed:
            return
        self.path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


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
        if not installations or not self.service_account_file.exists():
            return MobilePushResult(sent_count=0)

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
                        visibility="public",
                        default_sound=True,
                        default_vibrate_timings=True,
                    ),
                ),
                data={"alert_key": alert_key, "route": route},
            )
            for installation in installations
        ]
        response = messaging.send_each(messages)
        invalid_ids: list[str] = []
        for installation, result in zip(installations, response.responses):
            if result.success:
                continue
            code = getattr(getattr(result, "exception", None), "code", "")
            if code in {"registration-token-not-registered", "invalid-registration-token"}:
                invalid_ids.append(installation.installation_id)
        return MobilePushResult(
            sent_count=response.success_count,
            failed_count=response.failure_count,
            invalid_installation_ids=tuple(invalid_ids),
        )


class MobilePushDispatcher:
    def __init__(
        self,
        *,
        enabled: bool,
        include_recovery: bool,
        registry: MobilePushRegistry,
        sender: FirebaseMobilePushSender,
    ) -> None:
        self.enabled = enabled
        self.include_recovery = include_recovery
        self.registry = registry
        self.sender = sender

    @classmethod
    def from_config(cls, config: BotConfig) -> MobilePushDispatcher:
        return cls(
            enabled=config.mobile_push_enabled,
            include_recovery=config.mobile_push_include_recovery,
            registry=MobilePushRegistry(Path(config.mobile_push_token_registry_file)),
            sender=FirebaseMobilePushSender(Path(config.firebase_service_account_file)),
        )

    async def dispatch(
        self,
        *,
        alerts: list[Alert],
        recoveries: list[RecoveryNotice],
    ) -> None:
        if not self.enabled:
            return
        installations = self.registry.enabled_installations()
        if not installations:
            return
        for alert in alerts:
            if not _is_mobile_alert_key(alert.key):
                continue
            title, body, route = _format_mobile_alert(alert)
            await self._safe_send(
                installations=installations,
                title=title,
                body=body,
                route=route,
                alert_key=alert.key,
            )
        if not self.include_recovery:
            return
        for recovery in recoveries:
            if not _is_mobile_alert_key(recovery.key):
                continue
            title, body, route = _format_mobile_recovery(recovery)
            await self._safe_send(
                installations=installations,
                title=title,
                body=body,
                route=route,
                alert_key=recovery.key,
            )

    async def _safe_send(
        self,
        *,
        installations: list[MobilePushInstallation],
        title: str,
        body: str,
        route: str,
        alert_key: str,
    ) -> None:
        try:
            result = self.sender.send(
                installations=installations,
                title=title,
                body=body,
                route=route,
                alert_key=alert_key,
            )
            if result.invalid_installation_ids:
                self.registry.disable_installations(result.invalid_installation_ids)
            logger.info(
                "Mobile push alert_key=%s sent=%s failed=%s invalid=%s",
                alert_key,
                result.sent_count,
                result.failed_count,
                len(result.invalid_installation_ids),
            )
        except Exception:
            logger.exception("Mobile push send failed for alert_key=%s", alert_key)


def _is_mobile_alert_key(key: str) -> bool:
    return key in {"cpu-usage", "gpu-usage", "memory-usage"} or key.startswith("disk-usage:")


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
    return title, alert.message, _route_for_key(alert.key)


def _format_mobile_recovery(recovery: RecoveryNotice) -> tuple[str, str, str]:
    title = {
        "cpu-usage": "CPU usage recovered",
        "gpu-usage": "GPU usage recovered",
        "memory-usage": "RAM usage recovered",
    }.get(recovery.key, "Storage recovered")
    minutes = max(1, round(recovery.was_active_for_seconds / 60))
    return title, f"{recovery.title} recovered after about {minutes} minute(s).", _route_for_key(recovery.key)
