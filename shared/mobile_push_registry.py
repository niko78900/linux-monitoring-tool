from __future__ import annotations

import contextlib
import json
import os
import tempfile
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable, Iterator


REGISTRY_FILE_MODE = 0o640
LOCK_FILE_MODE = 0o660


@dataclass(frozen=True)
class MobilePushInstallation:
    installation_id: str
    device_name: str
    fcm_token: str
    platform: str
    enabled: bool
    include_recovery: bool
    last_registered_at: datetime
    last_test_sent_at: datetime | None = None

    @classmethod
    def from_json(cls, payload: dict[str, Any]) -> MobilePushInstallation | None:
        installation_id = str(payload.get("installation_id") or "").strip()
        device_name = str(payload.get("device_name") or "").strip()
        fcm_token = str(payload.get("fcm_token") or "").strip()
        platform = str(payload.get("platform") or "android").strip()
        last_registered_at = _parse_datetime(payload.get("last_registered_at"))
        if (
            not installation_id
            or not device_name
            or not fcm_token
            or last_registered_at is None
        ):
            return None
        return cls(
            installation_id=installation_id,
            device_name=device_name,
            fcm_token=fcm_token,
            platform=platform,
            enabled=_parse_bool(payload.get("enabled"), default=True),
            include_recovery=_parse_bool(
                payload.get("include_recovery"),
                default=True,
            ),
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
            "include_recovery": self.include_recovery,
            "last_registered_at": self.last_registered_at.isoformat(),
            "last_test_sent_at": self.last_test_sent_at.isoformat()
            if self.last_test_sent_at
            else None,
        }


class MobilePushRegistryFormatError(ValueError):
    pass


class LockedMobilePushRegistry:
    def __init__(self, path: Path) -> None:
        self.path = path
        self.lock_path = path.with_suffix(".lock")

    def get(self, installation_id: str) -> MobilePushInstallation | None:
        with self._locked():
            return self._load_unlocked().get(installation_id)

    def enabled_installations(self) -> list[MobilePushInstallation]:
        with self._locked():
            return [
                item
                for item in self._load_unlocked().values()
                if item.enabled and item.fcm_token.strip()
            ]

    def upsert(
        self,
        *,
        installation_id: str,
        device_name: str,
        fcm_token: str,
        platform: str = "android",
        enabled: bool = True,
        include_recovery: bool = True,
    ) -> MobilePushInstallation:
        def mutate(
            records: dict[str, MobilePushInstallation],
        ) -> MobilePushInstallation:
            existing = records.get(installation_id.strip())
            installation = MobilePushInstallation(
                installation_id=installation_id.strip(),
                device_name=device_name.strip(),
                fcm_token=fcm_token.strip(),
                platform=platform,
                enabled=enabled,
                include_recovery=include_recovery,
                last_registered_at=datetime.now(timezone.utc),
                last_test_sent_at=existing.last_test_sent_at if existing else None,
            )
            records[installation.installation_id] = installation
            return installation

        return self.update(mutate)

    def disable(self, installation_id: str) -> MobilePushInstallation | None:
        def mutate(
            records: dict[str, MobilePushInstallation],
        ) -> MobilePushInstallation | None:
            current = records.get(installation_id)
            if current is None:
                return None
            disabled = MobilePushInstallation(
                installation_id=current.installation_id,
                device_name=current.device_name,
                fcm_token=current.fcm_token,
                platform=current.platform,
                enabled=False,
                include_recovery=current.include_recovery,
                last_registered_at=current.last_registered_at,
                last_test_sent_at=current.last_test_sent_at,
            )
            records[installation_id] = disabled
            return disabled

        return self.update(mutate)

    def disable_installations(self, installation_ids: set[str]) -> None:
        ids = {item for item in installation_ids if item}
        if not ids:
            return

        def mutate(records: dict[str, MobilePushInstallation]) -> None:
            for installation_id in ids:
                current = records.get(installation_id)
                if current is not None:
                    records[installation_id] = MobilePushInstallation(
                        installation_id=current.installation_id,
                        device_name=current.device_name,
                        fcm_token=current.fcm_token,
                        platform=current.platform,
                        enabled=False,
                        include_recovery=current.include_recovery,
                        last_registered_at=current.last_registered_at,
                        last_test_sent_at=current.last_test_sent_at,
                    )

        self.update(mutate)

    def mark_test_sent(self, installation_id: str) -> MobilePushInstallation | None:
        def mutate(
            records: dict[str, MobilePushInstallation],
        ) -> MobilePushInstallation | None:
            current = records.get(installation_id)
            if current is None:
                return None
            updated = MobilePushInstallation(
                installation_id=current.installation_id,
                device_name=current.device_name,
                fcm_token=current.fcm_token,
                platform=current.platform,
                enabled=current.enabled,
                include_recovery=current.include_recovery,
                last_registered_at=current.last_registered_at,
                last_test_sent_at=datetime.now(timezone.utc),
            )
            records[installation_id] = updated
            return updated

        return self.update(mutate)

    def update(self, mutate: Callable[[dict[str, MobilePushInstallation]], Any]) -> Any:
        with self._locked():
            records = self._load_unlocked()
            result = mutate(records)
            self._save_unlocked(records)
            return result

    @contextlib.contextmanager
    def _locked(self) -> Iterator[None]:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        lock_handle = self.lock_path.open("a+b")
        try:
            _chmod_if_possible(self.lock_path, LOCK_FILE_MODE)
            _chown_gid_if_possible(self.lock_path, _target_gid(self.path))
            _lock_file(lock_handle)
            yield
        finally:
            try:
                _unlock_file(lock_handle)
            finally:
                lock_handle.close()

    def _load_unlocked(self) -> dict[str, MobilePushInstallation]:
        if not self.path.exists():
            return {}
        try:
            payload = json.loads(self.path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as error:
            raise MobilePushRegistryFormatError(
                f"Mobile push registry is malformed: {self.path}"
            ) from error
        except OSError as error:
            raise MobilePushRegistryFormatError(
                f"Mobile push registry is unreadable: {self.path}"
            ) from error
        raw_installations = payload.get("installations")
        if raw_installations is None:
            return {}
        if not isinstance(raw_installations, list):
            raise MobilePushRegistryFormatError(
                f"Mobile push registry installations must be a list: {self.path}"
            )

        records: dict[str, MobilePushInstallation] = {}
        for raw in raw_installations:
            if not isinstance(raw, dict):
                continue
            installation = MobilePushInstallation.from_json(raw)
            if installation is not None:
                records[installation.installation_id] = installation
        return records

    def _save_unlocked(self, records: dict[str, MobilePushInstallation]) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        payload = {
            "installations": [
                record.to_json()
                for record in sorted(
                    records.values(),
                    key=lambda item: item.installation_id,
                )
            ]
        }
        target_gid = _target_gid(self.path)
        fd, temp_name = tempfile.mkstemp(
            prefix=f".{self.path.name}.",
            suffix=".tmp",
            dir=str(self.path.parent),
            text=True,
        )
        temp_path = Path(temp_name)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                json.dump(payload, handle, indent=2, sort_keys=True)
                handle.write("\n")
            _chmod_if_possible(temp_path, REGISTRY_FILE_MODE)
            _chown_gid_if_possible(temp_path, target_gid)
            _replace_state_file(temp_path, self.path)
            _chmod_if_possible(self.path, REGISTRY_FILE_MODE)
            _chown_gid_if_possible(self.path, target_gid)
        finally:
            if temp_path.exists():
                temp_path.unlink()


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


def _replace_state_file(source: Path, target: Path) -> None:
    try:
        os.replace(source, target)
    except PermissionError:
        if os.name != "nt":
            raise
        target.unlink(missing_ok=True)
        os.replace(source, target)


def _lock_file(handle: Any) -> None:
    if os.name == "nt":
        import msvcrt

        handle.seek(0)
        msvcrt.locking(handle.fileno(), msvcrt.LK_LOCK, 1)
        return

    import fcntl

    fcntl.flock(handle.fileno(), fcntl.LOCK_EX)


def _unlock_file(handle: Any) -> None:
    if os.name == "nt":
        import msvcrt

        handle.seek(0)
        msvcrt.locking(handle.fileno(), msvcrt.LK_UNLCK, 1)
        return

    import fcntl

    fcntl.flock(handle.fileno(), fcntl.LOCK_UN)


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


def _parse_bool(value: object, *, default: bool) -> bool:
    if value is None:
        return default
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        normalized = value.strip().lower()
        if normalized in {"1", "true", "yes", "on"}:
            return True
        if normalized in {"0", "false", "no", "off"}:
            return False
        return default
    return bool(value)
