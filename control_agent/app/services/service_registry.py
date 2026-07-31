from __future__ import annotations

import json
import logging
import subprocess
from collections.abc import Callable
from datetime import datetime, timezone
from pathlib import Path
from urllib import error, request

import yaml

from ..models.services import (
    ManagedServiceStatus,
    ManagedServicesResponse,
    ServiceAction,
    ServiceActionRecord,
    ServiceConfig,
    ServicesConfigDocument,
)

SubprocessRunner = Callable[..., subprocess.CompletedProcess[str]]

logger = logging.getLogger(__name__)


class ServiceActionStateStore:
    def __init__(self, path: Path):
        self.path = path

    def get(self, service_id: str) -> ServiceActionRecord | None:
        return self.load_all().get(service_id)

    def set(self, service_id: str, record: ServiceActionRecord) -> None:
        records = self.load_all()
        records[service_id] = record
        self._write(records)

    def load_all(self) -> dict[str, ServiceActionRecord]:
        try:
            raw = json.loads(self.path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            return {}
        if not isinstance(raw, dict):
            return {}

        records: dict[str, ServiceActionRecord] = {}
        for service_id, payload in raw.items():
            if not isinstance(service_id, str) or not isinstance(payload, dict):
                continue
            try:
                records[service_id] = ServiceActionRecord.model_validate(payload)
            except ValueError:
                continue
        return records

    def _write(self, records: dict[str, ServiceActionRecord]) -> None:
        payload = {
            service_id: record.model_dump(mode="json")
            for service_id, record in records.items()
        }
        try:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            temporary_path = self.path.with_name(f"{self.path.name}.tmp")
            temporary_path.write_text(
                json.dumps(payload, indent=2, sort_keys=True),
                encoding="utf-8",
            )
            temporary_path.replace(self.path)
        except OSError as error:
            logger.warning("Could not persist service action state: %s", error)


def load_service_registry(path: Path) -> list[ServiceConfig]:
    try:
        raw_text = path.read_text(encoding="utf-8")
    except OSError as err:
        raise ValueError(f"Could not read services config: {path}") from err

    try:
        payload = yaml.safe_load(raw_text) or {}
    except yaml.YAMLError as err:
        raise ValueError("Services config is not valid YAML") from err

    document = ServicesConfigDocument.model_validate(payload)
    ids = [service.id for service in document.services]
    duplicate_ids = {service_id for service_id in ids if ids.count(service_id) > 1}
    if duplicate_ids:
        duplicates = ", ".join(sorted(duplicate_ids))
        raise ValueError(f"Service IDs must be unique: {duplicates}")
    return document.services


def list_service_statuses(
    services: list[ServiceConfig],
    *,
    subprocess_runner: SubprocessRunner | None = None,
    url_opener: Callable[..., object] | None = None,
    action_store: ServiceActionStateStore | None = None,
) -> ManagedServicesResponse:
    runner = subprocess_runner or subprocess.run
    opener = url_opener or request.urlopen
    return ManagedServicesResponse(
        services=[
            get_service_status(
                service,
                subprocess_runner=runner,
                url_opener=opener,
                action_store=action_store,
            )
            for service in services
        ]
    )


def get_service_status(
    service: ServiceConfig,
    *,
    subprocess_runner: SubprocessRunner | None = None,
    url_opener: Callable[..., object] | None = None,
    action_store: ServiceActionStateStore | None = None,
) -> ManagedServiceStatus:
    runner = subprocess_runner or subprocess.run
    opener = url_opener or request.urlopen
    runtime_state = _read_runtime_state(service, subprocess_runner=runner)
    health_state = _probe_health(service, url_opener=opener)
    return ManagedServiceStatus(
        service_id=service.id,
        display_name=service.display_name,
        host_id=service.host_id,
        runtime_type=service.adapter,
        runtime_target=service.target,
        runtime_state=runtime_state,
        health_probe_state=health_state,
        category=service.category,
        description=service.description,
        url=service.url,
        ports=service.ports,
        image=service.image,
        last_checked=datetime.now(timezone.utc),
        allowed_actions=list(service.allowed_actions),
        last_action=action_store.get(service.id) if action_store else None,
    )


def execute_service_action(
    services: list[ServiceConfig],
    *,
    service_id: str,
    action: ServiceAction,
    helper_path: Path,
    timeout_seconds: int,
    subprocess_runner: SubprocessRunner | None = None,
    action_store: ServiceActionStateStore | None = None,
) -> ServiceActionRecord:
    runner = subprocess_runner or subprocess.run
    service = next((item for item in services if item.id == service_id), None)
    if service is None:
        raise LookupError("Unknown service")
    if action not in service.allowed_actions:
        raise PermissionError("Action is not allowed for this service")

    requested_at = datetime.now(timezone.utc)
    args = [str(helper_path), service.id, action]
    try:
        result = runner(
            args,
            capture_output=True,
            text=True,
            check=False,
            timeout=timeout_seconds,
        )
    except FileNotFoundError as err:
        record = ServiceActionRecord(
            action=action,
            status="failed",
            requested_at=requested_at,
            detail="Service control helper is not installed.",
        )
        _store_action(action_store, service.id, record)
        raise RuntimeError(record.detail) from err
    except subprocess.TimeoutExpired as err:
        record = ServiceActionRecord(
            action=action,
            status="failed",
            requested_at=requested_at,
            detail="Service control helper timed out.",
        )
        _store_action(action_store, service.id, record)
        raise RuntimeError(record.detail) from err

    if result.returncode != 0:
        record = ServiceActionRecord(
            action=action,
            status="failed",
            requested_at=requested_at,
            detail=(result.stderr or result.stdout or "Service action failed").strip(),
        )
        _store_action(action_store, service.id, record)
        raise RuntimeError(record.detail or "Service action failed")

    record = ServiceActionRecord(
        action=action,
        status="accepted",
        requested_at=requested_at,
        detail=(result.stdout or "accepted").strip(),
    )
    _store_action(action_store, service.id, record)
    return record


def _store_action(
    action_store: ServiceActionStateStore | None,
    service_id: str,
    record: ServiceActionRecord,
) -> None:
    if action_store is not None:
        action_store.set(service_id, record)


def _read_runtime_state(
    service: ServiceConfig,
    *,
    subprocess_runner: SubprocessRunner,
) -> str:
    args = (
        ["docker", "inspect", "--format", "{{.State.Status}}", service.target]
        if service.adapter == "docker"
        else ["systemctl", "is-active", service.target]
    )
    try:
        result = subprocess_runner(
            args,
            capture_output=True,
            text=True,
            check=False,
            timeout=service.health_probe.timeout_seconds if service.health_probe else 3,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return "unavailable"

    output = (result.stdout or result.stderr or "").strip().lower()
    if service.adapter == "docker" and result.returncode != 0:
        return "unavailable"
    if result.returncode != 0 and not output:
        return "unavailable"
    return output or "unknown"


def _probe_health(
    service: ServiceConfig,
    *,
    url_opener: Callable[..., object],
) -> str:
    if service.health_probe is None or service.health_probe.type != "http":
        return "unconfigured"

    try:
        response = url_opener(
            service.health_probe.url,
            timeout=service.health_probe.timeout_seconds,
        )
        status_code = getattr(response, "status", 200)
        return "healthy" if 200 <= status_code < 400 else "unhealthy"
    except error.URLError:
        return "unreachable"
    except TimeoutError:
        return "timeout"
