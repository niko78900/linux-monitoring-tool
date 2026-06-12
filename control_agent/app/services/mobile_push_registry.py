from __future__ import annotations

import json
import os
import tempfile
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from ..models.mobile_alerts import (
    MobileAlertRegistrationRequest,
    MobileAlertStatusResponse,
)


@dataclass(frozen=True)
class MobilePushInstallation:
    installation_id: str
    device_name: str
    fcm_token: str
    platform: str
    enabled: bool
    last_registered_at: datetime
    last_test_sent_at: datetime | None = None

    @classmethod
    def from_json(cls, payload: dict[str, Any]) -> MobilePushInstallation | None:
        installation_id = str(payload.get("installation_id") or "").strip()
        device_name = str(payload.get("device_name") or "").strip()
        fcm_token = str(payload.get("fcm_token") or "").strip()
        platform = str(payload.get("platform") or "android").strip()
        last_registered_at = _parse_datetime(payload.get("last_registered_at"))
        if not installation_id or not device_name or not fcm_token or last_registered_at is None:
            return None
        return cls(
            installation_id=installation_id,
            device_name=device_name,
            fcm_token=fcm_token,
            platform=platform,
            enabled=bool(payload.get("enabled", True)),
            last_registered_at=last_registered_at,
            last_test_sent_at=_parse_datetime(payload.get("last_test_sent_at")),
        )

    def to_json(self) -> dict[str, Any]:
        return {
            "installation_id": self.installation_id,
            "device_name": self.device_name,
            "fcm_token": self.fcm_token,
            "platform": self.platform,
            "enabled": self.enabled,
            "last_registered_at": self.last_registered_at.isoformat(),
            "last_test_sent_at": self.last_test_sent_at.isoformat()
            if self.last_test_sent_at
            else None,
        }


class MobilePushTokenRegistry:
    def __init__(self, path: Path) -> None:
        self.path = path

    def get(self, installation_id: str) -> MobilePushInstallation | None:
        return self._load().get(installation_id)

    def enabled_installations(self) -> list[MobilePushInstallation]:
        return [
            item
            for item in self._load().values()
            if item.enabled and item.fcm_token.strip()
        ]

    def upsert(
        self, request: MobileAlertRegistrationRequest
    ) -> MobilePushInstallation:
        records = self._load()
        installation = MobilePushInstallation(
            installation_id=request.installation_id.strip(),
            device_name=request.device_name.strip(),
            fcm_token=request.fcm_token.strip(),
            platform=request.platform,
            enabled=request.enabled,
            last_registered_at=datetime.now(timezone.utc),
            last_test_sent_at=records.get(request.installation_id.strip()).last_test_sent_at
            if records.get(request.installation_id.strip())
            else None,
        )
        records[installation.installation_id] = installation
        self._save(records)
        return installation

    def disable(self, installation_id: str) -> MobilePushInstallation | None:
        records = self._load()
        current = records.get(installation_id)
        if current is None:
            return None
        disabled = MobilePushInstallation(
            installation_id=current.installation_id,
            device_name=current.device_name,
            fcm_token=current.fcm_token,
            platform=current.platform,
            enabled=False,
            last_registered_at=current.last_registered_at,
            last_test_sent_at=current.last_test_sent_at,
        )
        records[installation_id] = disabled
        self._save(records)
        return disabled

    def mark_test_sent(self, installation_id: str) -> MobilePushInstallation | None:
        records = self._load()
        current = records.get(installation_id)
        if current is None:
            return None
        updated = MobilePushInstallation(
            installation_id=current.installation_id,
            device_name=current.device_name,
            fcm_token=current.fcm_token,
            platform=current.platform,
            enabled=current.enabled,
            last_registered_at=current.last_registered_at,
            last_test_sent_at=datetime.now(timezone.utc),
        )
        records[installation_id] = updated
        self._save(records)
        return updated

    def status(
        self, *, installation_id: str | None, push_configured: bool
    ) -> MobileAlertStatusResponse:
        installation = self.get(installation_id) if installation_id else None
        if installation is None or not installation.enabled:
            return MobileAlertStatusResponse(
                push_configured=push_configured,
                registered=False,
                installation_id=installation_id,
            )
        return MobileAlertStatusResponse(
            push_configured=push_configured,
            registered=True,
            installation_id=installation.installation_id,
            device_name=installation.device_name,
            platform=installation.platform,
            enabled=installation.enabled,
            last_registered_at=installation.last_registered_at,
            last_test_sent_at=installation.last_test_sent_at,
        )

    def _load(self) -> dict[str, MobilePushInstallation]:
        if not self.path.exists():
            return {}
        try:
            payload = json.loads(self.path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            return {}
        raw_installations = payload.get("installations")
        if not isinstance(raw_installations, list):
            return {}
        records: dict[str, MobilePushInstallation] = {}
        for raw in raw_installations:
            if not isinstance(raw, dict):
                continue
            installation = MobilePushInstallation.from_json(raw)
            if installation is not None:
                records[installation.installation_id] = installation
        return records

    def _save(self, records: dict[str, MobilePushInstallation]) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        payload = {
            "installations": [
                record.to_json() for record in sorted(records.values(), key=lambda item: item.installation_id)
            ]
        }
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
            os.chmod(temp_name, 0o600)
            os.replace(temp_name, self.path)
            try:
                os.chmod(self.path, 0o600)
            except OSError:
                pass
        finally:
            if os.path.exists(temp_name):
                os.unlink(temp_name)


def _parse_datetime(value: object) -> datetime | None:
    if not isinstance(value, str):
        return None
    try:
        parsed = datetime.fromisoformat(value)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)
