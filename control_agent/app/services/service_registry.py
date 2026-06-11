from __future__ import annotations

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

_last_actions: dict[str, ServiceActionRecord] = {}


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
) -> ManagedServicesResponse:
    runner = subprocess_runner or subprocess.run
    opener = url_opener or request.urlopen
    return ManagedServicesResponse(
        services=[
            get_service_status(
                service,
                subprocess_runner=runner,
                url_opener=opener,
            )
            for service in services
        ]
    )


def get_service_status(
    service: ServiceConfig,
    *,
    subprocess_runner: SubprocessRunner | None = None,
    url_opener: Callable[..., object] | None = None,
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
        runtime_state=runtime_state,
        health_probe_state=health_state,
        last_checked=datetime.now(timezone.utc),
        allowed_actions=list(service.allowed_actions),
        last_action=_last_actions.get(service.id),
    )


def execute_service_action(
    services: list[ServiceConfig],
    *,
    service_id: str,
    action: ServiceAction,
    helper_path: Path,
    timeout_seconds: int,
    subprocess_runner: SubprocessRunner | None = None,
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
        _last_actions[service.id] = record
        raise RuntimeError(record.detail) from err
    except subprocess.TimeoutExpired as err:
        record = ServiceActionRecord(
            action=action,
            status="failed",
            requested_at=requested_at,
            detail="Service control helper timed out.",
        )
        _last_actions[service.id] = record
        raise RuntimeError(record.detail) from err

    if result.returncode != 0:
        record = ServiceActionRecord(
            action=action,
            status="failed",
            requested_at=requested_at,
            detail=(result.stderr or result.stdout or "Service action failed").strip(),
        )
        _last_actions[service.id] = record
        raise RuntimeError(record.detail or "Service action failed")

    record = ServiceActionRecord(
        action=action,
        status="accepted",
        requested_at=requested_at,
        detail=(result.stdout or "accepted").strip(),
    )
    _last_actions[service.id] = record
    return record


def reset_service_action_records() -> None:
    _last_actions.clear()


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
