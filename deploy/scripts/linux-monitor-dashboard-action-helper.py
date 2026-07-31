#!/var/lib/homelab-venvs/linux-monitor-control-agent/bin/python
from __future__ import annotations

import ipaddress
import json
import os
import re
import socket
import stat
import subprocess
import sys
import time
from collections.abc import Callable
from pathlib import Path
from typing import Any
from urllib import error as url_error
from urllib import request as url_request
from urllib.parse import urlsplit
from uuid import UUID

import yaml

REGISTRY_PATH = Path("/etc/linux-monitor/dashboard-managed-actions.yml")
DOCKER_BINARY = "/usr/bin/docker"
SYSTEMCTL_BINARY = "/usr/bin/systemctl"
IP_BINARY = "/usr/sbin/ip"
MAX_INPUT_BYTES = 4096
MAX_REGISTRY_BYTES = 131072

ID_PATTERN = re.compile(r"^[a-z0-9](?:[a-z0-9-]{0,62}[a-z0-9])?$")
TARGET_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.@-]{0,127}$")
INTERFACE_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.:-]{0,31}$")
MAC_PATTERN = re.compile(r"^(?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$")
SAFE_STATE_PATTERN = re.compile(r"^[A-Za-z0-9_.:-]{1,64}$")
SHELL_METACHARACTERS = frozenset("$`;&|><\\\n\r")
SERVICE_ACTIONS = {"start", "stop", "restart"}
ALL_ACTIONS = SERVICE_ACTIONS | {"wake"}
FORBIDDEN_SYSTEMD_UNITS = {
    "containerd.service",
    "docker.service",
    "linux-monitor-dashboard-action.service",
    "linux-monitor-dashboard-read-bridge.service",
    "networking.service",
    "smbd.service",
    "ssh.service",
    "sshd.service",
    "tailscaled.service",
    "ufw.service",
}
FORBIDDEN_CONTAINERS = {"portainer"}
FORBIDDEN_CONTAINER_FRAGMENTS = (
    "dashboard-backend",
    "dashboard-frontend",
    "immich_machine_learning",
    "immich_postgres",
    "immich_redis",
)

CommandRunner = Callable[..., subprocess.CompletedProcess[str]]


class HelperFailure(RuntimeError):
    def __init__(
        self,
        code: str,
        summary: str,
        *,
        status_value: str = "failed",
        previous_state: str | None = None,
        resulting_state: str | None = None,
    ):
        super().__init__(summary)
        self.code = code
        self.summary = summary
        self.status_value = status_value
        self.previous_state = previous_state
        self.resulting_state = resulting_state


def load_registry(path: Path = REGISTRY_PATH, *, enforce_metadata: bool = True) -> dict[str, Any]:
    if not path.is_absolute():
        raise HelperFailure("registry_invalid", "Action registry validation failed.", status_value="rejected")
    try:
        metadata = path.lstat()
        parent_metadata = path.parent.stat()
    except OSError as error:
        raise HelperFailure("registry_unavailable", "Action registry is unavailable.", status_value="rejected") from error
    if enforce_metadata and (
        not stat.S_ISREG(metadata.st_mode)
        or metadata.st_uid != 0
        or metadata.st_gid != 0
        or stat.S_IMODE(metadata.st_mode) != 0o600
        or not stat.S_ISDIR(parent_metadata.st_mode)
        or parent_metadata.st_uid != 0
        or parent_metadata.st_gid != 0
        or stat.S_IMODE(parent_metadata.st_mode) & 0o022
    ):
        raise HelperFailure("registry_permissions", "Action registry permissions are invalid.", status_value="rejected")
    if metadata.st_size > MAX_REGISTRY_BYTES:
        raise HelperFailure("registry_too_large", "Action registry validation failed.", status_value="rejected")
    try:
        payload = yaml.safe_load(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, yaml.YAMLError) as error:
        raise HelperFailure("registry_invalid", "Action registry validation failed.", status_value="rejected") from error
    return validate_registry(payload)


def validate_registry(payload: object) -> dict[str, Any]:
    if not isinstance(payload, dict) or set(payload) - {"services", "wake_targets"}:
        raise HelperFailure("registry_invalid", "Action registry validation failed.", status_value="rejected")
    services = payload.get("services", [])
    wake_targets = payload.get("wake_targets", [])
    if not isinstance(services, list) or not isinstance(wake_targets, list) or len(wake_targets) > 1:
        raise HelperFailure("registry_invalid", "Action registry validation failed.", status_value="rejected")
    validated_services = [_validate_service(item) for item in services]
    validated_wake = [_validate_wake_target(item) for item in wake_targets]
    identifiers = [item["id"] for item in (*validated_services, *validated_wake)]
    if len(identifiers) != len(set(identifiers)):
        raise HelperFailure("registry_invalid", "Action registry validation failed.", status_value="rejected")
    return {"services": validated_services, "wake_targets": validated_wake}


def execute_request(
    payload: object,
    registry: dict[str, Any],
    *,
    runner: CommandRunner = subprocess.run,
    health_opener: Callable[..., object] = url_request.urlopen,
    socket_factory: Callable[..., socket.socket] = socket.socket,
) -> dict[str, str | None]:
    request_document = _validate_request(payload)
    service_id = request_document["service_id"]
    action = request_document["action"]
    service = next(
        (item for item in registry["services"] if item["id"] == service_id),
        None,
    )
    wake_target = next(
        (item for item in registry["wake_targets"] if item["id"] == service_id),
        None,
    )
    if service is not None:
        if action not in service["allowed_actions"]:
            raise HelperFailure("action_not_allowed", "Action is not allowed.", status_value="rejected")
        if service["kind"] == "docker_container":
            return _execute_docker_action(
                service,
                action,
                runner=runner,
                health_opener=health_opener,
            )
        if service["kind"] == "systemd":
            return _execute_systemd_action(
                service,
                action,
                runner=runner,
                health_opener=health_opener,
            )
    if wake_target is not None and action == "wake":
        return _execute_wake(
            wake_target,
            runner=runner,
            socket_factory=socket_factory,
        )
    raise HelperFailure("target_not_found", "Target is not allowed.", status_value="rejected")


def _validate_request(payload: object) -> dict[str, str]:
    if not isinstance(payload, dict) or set(payload) != {"service_id", "action", "action_id"}:
        raise HelperFailure("request_invalid", "Helper request is invalid.", status_value="rejected")
    if not all(isinstance(payload.get(key), str) for key in payload):
        raise HelperFailure("request_invalid", "Helper request is invalid.", status_value="rejected")
    service_id = payload["service_id"]
    action = payload["action"]
    action_id = payload["action_id"]
    if not ID_PATTERN.fullmatch(service_id) or action not in ALL_ACTIONS:
        raise HelperFailure("request_invalid", "Helper request is invalid.", status_value="rejected")
    try:
        parsed_id = UUID(action_id)
    except ValueError as error:
        raise HelperFailure("request_invalid", "Helper request is invalid.", status_value="rejected") from error
    if str(parsed_id) != action_id.lower():
        raise HelperFailure("request_invalid", "Helper request is invalid.", status_value="rejected")
    return {"service_id": service_id, "action": action, "action_id": action_id}


def _validate_service(payload: object) -> dict[str, Any]:
    common = {
        "id",
        "name",
        "kind",
        "allowed_actions",
        "timeout_seconds",
        "health_url",
        "confirmation_level",
        "container_name",
        "expected_compose_project",
        "expected_compose_service",
        "systemd_unit",
    }
    if not isinstance(payload, dict) or set(payload) - common:
        raise HelperFailure("registry_invalid", "Action registry validation failed.", status_value="rejected")
    service_id = _strict_string(payload.get("id"), ID_PATTERN)
    name = _display_name(payload.get("name"))
    kind = payload.get("kind")
    actions = payload.get("allowed_actions")
    if kind not in {"docker_container", "systemd"}:
        raise HelperFailure("registry_invalid", "Action registry validation failed.", status_value="rejected")
    if (
        not isinstance(actions, list)
        or not actions
        or len(actions) != len(set(actions))
        or any(action not in SERVICE_ACTIONS for action in actions)
    ):
        raise HelperFailure("registry_invalid", "Action registry validation failed.", status_value="rejected")
    timeout = _bounded_int(payload.get("timeout_seconds", 90), 5, 300)
    health_url = _health_url(payload.get("health_url"))
    confirmation = payload.get("confirmation_level", "normal")
    if confirmation not in {"normal", "high"}:
        raise HelperFailure("registry_invalid", "Action registry validation failed.", status_value="rejected")

    validated: dict[str, Any] = {
        "id": service_id,
        "name": name,
        "kind": kind,
        "allowed_actions": list(actions),
        "timeout_seconds": timeout,
        "health_url": health_url,
        "confirmation_level": confirmation,
    }
    if kind == "docker_container":
        required = ("container_name", "expected_compose_project", "expected_compose_service")
        if payload.get("systemd_unit") is not None or any(payload.get(key) is None for key in required):
            raise HelperFailure("registry_invalid", "Action registry validation failed.", status_value="rejected")
        for key in required:
            validated[key] = _strict_string(payload[key], TARGET_PATTERN)
        container = validated["container_name"]
        if container in FORBIDDEN_CONTAINERS or any(fragment in container for fragment in FORBIDDEN_CONTAINER_FRAGMENTS):
            raise HelperFailure("registry_excluded", "Registry contains an excluded target.", status_value="rejected")
    else:
        if any(payload.get(key) is not None for key in ("container_name", "expected_compose_project", "expected_compose_service")):
            raise HelperFailure("registry_invalid", "Action registry validation failed.", status_value="rejected")
        unit = _strict_string(payload.get("systemd_unit"), TARGET_PATTERN)
        if not unit.endswith(".service") or unit in FORBIDDEN_SYSTEMD_UNITS:
            raise HelperFailure("registry_excluded", "Registry contains an excluded target.", status_value="rejected")
        validated["systemd_unit"] = unit
    return validated


def _validate_wake_target(payload: object) -> dict[str, Any]:
    allowed_keys = {
        "id",
        "name",
        "allowed_actions",
        "mac_address",
        "broadcast_address",
        "interface",
        "port",
        "timeout_seconds",
        "confirmation_level",
    }
    if not isinstance(payload, dict) or set(payload) - allowed_keys:
        raise HelperFailure("registry_invalid", "Action registry validation failed.", status_value="rejected")
    if payload.get("id") != "main-pc" or payload.get("allowed_actions") != ["wake"]:
        raise HelperFailure("registry_invalid", "Action registry validation failed.", status_value="rejected")
    name = _display_name(payload.get("name"))
    mac = payload.get("mac_address")
    interface = _strict_string(payload.get("interface"), INTERFACE_PATTERN)
    if not isinstance(mac, str) or not MAC_PATTERN.fullmatch(mac):
        raise HelperFailure("registry_invalid", "Action registry validation failed.", status_value="rejected")
    try:
        broadcast = ipaddress.IPv4Address(payload.get("broadcast_address"))
    except (ipaddress.AddressValueError, TypeError) as error:
        raise HelperFailure("registry_invalid", "Action registry validation failed.", status_value="rejected") from error
    if broadcast.is_loopback or broadcast.is_multicast or broadcast.is_unspecified:
        raise HelperFailure("registry_invalid", "Action registry validation failed.", status_value="rejected")
    confirmation = payload.get("confirmation_level", "normal")
    if confirmation not in {"normal", "high"}:
        raise HelperFailure("registry_invalid", "Action registry validation failed.", status_value="rejected")
    return {
        "id": "main-pc",
        "name": name,
        "allowed_actions": ["wake"],
        "mac_address": mac.upper(),
        "broadcast_address": str(broadcast),
        "interface": interface,
        "port": _bounded_int(payload.get("port", 9), 1, 65535),
        "timeout_seconds": _bounded_int(payload.get("timeout_seconds", 10), 1, 30),
        "confirmation_level": confirmation,
    }


def _execute_docker_action(
    service: dict[str, Any],
    action: str,
    *,
    runner: CommandRunner,
    health_opener: Callable[..., object],
) -> dict[str, str | None]:
    container = service["container_name"]
    _verify_container_identity(service, runner=runner)
    previous_state = _docker_state(container, runner=runner)
    timeout = service["timeout_seconds"]
    if action == "start":
        arguments = [DOCKER_BINARY, "start", container]
    elif action == "stop":
        arguments = [DOCKER_BINARY, "stop", "--time", str(timeout), container]
    else:
        arguments = [DOCKER_BINARY, "restart", "--time", str(timeout), container]
    result = _run(arguments, runner=runner, timeout=timeout + 5)
    if result.returncode != 0:
        raise HelperFailure("operation_failed", "Container action failed.", previous_state=previous_state)

    resulting_state = _docker_state(container, runner=runner)
    expected_state = "exited" if action == "stop" else "running"
    if resulting_state != expected_state:
        raise HelperFailure(
            "state_mismatch",
            "Container did not reach the expected state.",
            previous_state=previous_state,
            resulting_state=resulting_state,
        )
    if action != "stop" and service.get("health_url"):
        _wait_for_health(
            service["health_url"],
            timeout_seconds=timeout,
            opener=health_opener,
        )
    summary = {
        "start": "Container is running and its health check passed.",
        "stop": "Container stopped successfully.",
        "restart": "Container restarted and its health check passed.",
    }[action]
    return _success(summary, previous_state, resulting_state)


def _execute_systemd_action(
    service: dict[str, Any],
    action: str,
    *,
    runner: CommandRunner,
    health_opener: Callable[..., object],
) -> dict[str, str | None]:
    unit = service["systemd_unit"]
    previous_state = _systemd_state(unit, runner=runner)
    timeout = service["timeout_seconds"]
    result = _run(
        [SYSTEMCTL_BINARY, action, unit],
        runner=runner,
        timeout=timeout,
    )
    if result.returncode != 0:
        raise HelperFailure("operation_failed", "System service action failed.", previous_state=previous_state)
    resulting_state = _systemd_state(unit, runner=runner)
    expected_state = "inactive" if action == "stop" else "active"
    if resulting_state != expected_state:
        raise HelperFailure(
            "state_mismatch",
            "System service did not reach the expected state.",
            previous_state=previous_state,
            resulting_state=resulting_state,
        )
    if action != "stop" and service.get("health_url"):
        _wait_for_health(service["health_url"], timeout_seconds=timeout, opener=health_opener)
    return _success("System service action completed.", previous_state, resulting_state)


def _execute_wake(
    target: dict[str, Any],
    *,
    runner: CommandRunner,
    socket_factory: Callable[..., socket.socket],
) -> dict[str, str | None]:
    _validate_live_interface(target, runner=runner)
    normalized_mac = target["mac_address"].replace(":", "")
    packet = b"\xff" * 6 + bytes.fromhex(normalized_mac) * 16
    with socket_factory(socket.AF_INET, socket.SOCK_DGRAM) as wake_socket:
        wake_socket.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        if hasattr(socket, "SO_BINDTODEVICE"):
            wake_socket.setsockopt(
                socket.SOL_SOCKET,
                socket.SO_BINDTODEVICE,
                target["interface"].encode("ascii") + b"\0",
            )
        wake_socket.sendto(
            packet,
            (target["broadcast_address"], target["port"]),
        )
    return _success("Wake-on-LAN magic packet sent.", "unknown", "packet-sent")


def _verify_container_identity(service: dict[str, Any], *, runner: CommandRunner) -> None:
    container = service["container_name"]
    project = _docker_inspect_field(
        container,
        '{{index .Config.Labels "com.docker.compose.project"}}',
        runner=runner,
    )
    compose_service = _docker_inspect_field(
        container,
        '{{index .Config.Labels "com.docker.compose.service"}}',
        runner=runner,
    )
    if project != service["expected_compose_project"] or compose_service != service["expected_compose_service"]:
        raise HelperFailure("target_identity_mismatch", "Container identity validation failed.", status_value="rejected")


def _docker_state(container: str, *, runner: CommandRunner) -> str:
    state = _docker_inspect_field(container, "{{.State.Status}}", runner=runner).lower()
    if not SAFE_STATE_PATTERN.fullmatch(state):
        raise HelperFailure("state_invalid", "Container state could not be validated.")
    return state


def _docker_inspect_field(container: str, template: str, *, runner: CommandRunner) -> str:
    result = _run(
        [DOCKER_BINARY, "inspect", "--format", template, container],
        runner=runner,
        timeout=5,
    )
    value = result.stdout.strip()
    if result.returncode != 0 or not value or "\n" in value or "\r" in value or len(value) > 128:
        raise HelperFailure("target_unavailable", "Container target is unavailable.")
    return value


def _systemd_state(unit: str, *, runner: CommandRunner) -> str:
    result = _run(
        [SYSTEMCTL_BINARY, "is-active", unit],
        runner=runner,
        timeout=5,
    )
    value = (result.stdout or "unknown").strip().lower()
    if not SAFE_STATE_PATTERN.fullmatch(value):
        raise HelperFailure("state_invalid", "System service state could not be validated.")
    return value


def _wait_for_health(
    health_url: str,
    *,
    timeout_seconds: int,
    opener: Callable[..., object],
) -> None:
    deadline = time.monotonic() + timeout_seconds
    while time.monotonic() < deadline:
        try:
            response = opener(health_url, timeout=min(2, timeout_seconds))
            status_code = getattr(response, "status", 200)
            close = getattr(response, "close", None)
            if callable(close):
                close()
            if 200 <= status_code < 400:
                return
        except (OSError, TimeoutError, url_error.URLError):
            pass
        time.sleep(0.25)
    raise HelperFailure("health_timeout", "Target health check did not recover.", status_value="timed_out")


def _validate_live_interface(target: dict[str, Any], *, runner: CommandRunner) -> None:
    interface = target["interface"]
    try:
        socket.if_nametoindex(interface)
    except OSError as error:
        raise HelperFailure("wake_interface_invalid", "Wake interface is unavailable.", status_value="rejected") from error
    result = _run(
        [IP_BINARY, "-j", "address", "show", "dev", interface],
        runner=runner,
        timeout=5,
    )
    try:
        links = json.loads(result.stdout)
        broadcasts = {
            item["broadcast"]
            for link in links
            for item in link.get("addr_info", [])
            if item.get("family") == "inet" and item.get("broadcast")
        }
    except (KeyError, TypeError, json.JSONDecodeError) as error:
        raise HelperFailure("wake_interface_invalid", "Wake interface validation failed.", status_value="rejected") from error
    configured = target["broadcast_address"]
    if configured != "255.255.255.255" and configured not in broadcasts:
        raise HelperFailure("wake_broadcast_invalid", "Wake broadcast validation failed.", status_value="rejected")


def _run(
    arguments: list[str],
    *,
    runner: CommandRunner,
    timeout: int,
) -> subprocess.CompletedProcess[str]:
    try:
        return runner(
            arguments,
            capture_output=True,
            text=True,
            check=False,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired as error:
        raise HelperFailure("operation_timeout", "Action timed out.", status_value="timed_out") from error
    except OSError as error:
        raise HelperFailure("runtime_unavailable", "Required runtime is unavailable.") from error


def _success(summary: str, previous_state: str, resulting_state: str) -> dict[str, str | None]:
    return {
        "status": "succeeded",
        "summary": summary,
        "error_code": None,
        "previous_state": previous_state,
        "resulting_state": resulting_state,
    }


def _strict_string(value: object, pattern: re.Pattern[str]) -> str:
    if not isinstance(value, str):
        raise HelperFailure("registry_invalid", "Action registry validation failed.", status_value="rejected")
    normalized = value.strip()
    if (
        not normalized
        or any(character in SHELL_METACHARACTERS for character in normalized)
        or not pattern.fullmatch(normalized)
    ):
        raise HelperFailure("registry_invalid", "Action registry validation failed.", status_value="rejected")
    return normalized


def _display_name(value: object) -> str:
    if not isinstance(value, str):
        raise HelperFailure("registry_invalid", "Action registry validation failed.", status_value="rejected")
    normalized = value.strip()
    if not normalized or len(normalized) > 80 or any(character in SHELL_METACHARACTERS for character in normalized):
        raise HelperFailure("registry_invalid", "Action registry validation failed.", status_value="rejected")
    return normalized


def _bounded_int(value: object, minimum: int, maximum: int) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or not minimum <= value <= maximum:
        raise HelperFailure("registry_invalid", "Action registry validation failed.", status_value="rejected")
    return value


def _health_url(value: object) -> str | None:
    if value is None:
        return None
    if not isinstance(value, str):
        raise HelperFailure("registry_invalid", "Action registry validation failed.", status_value="rejected")
    parsed = urlsplit(value)
    try:
        port = parsed.port
    except ValueError as error:
        raise HelperFailure("registry_invalid", "Action registry validation failed.", status_value="rejected") from error
    if (
        parsed.scheme != "http"
        or parsed.hostname not in {"127.0.0.1", "localhost"}
        or port is None
        or parsed.username
        or parsed.password
        or parsed.fragment
    ):
        raise HelperFailure("registry_invalid", "Action registry validation failed.", status_value="rejected")
    return value


def _read_request() -> object:
    raw = sys.stdin.buffer.read(MAX_INPUT_BYTES + 1)
    if len(raw) > MAX_INPUT_BYTES:
        raise HelperFailure("request_too_large", "Helper request is invalid.", status_value="rejected")
    try:
        return json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise HelperFailure("request_invalid", "Helper request is invalid.", status_value="rejected") from error


def _failure_payload(error: HelperFailure) -> dict[str, str | None]:
    return {
        "status": error.status_value,
        "summary": error.summary,
        "error_code": error.code,
        "previous_state": error.previous_state,
        "resulting_state": error.resulting_state,
    }


def main() -> int:
    if os.geteuid() != 0:
        response = _failure_payload(
            HelperFailure("root_required", "Action helper requires its restricted root boundary.", status_value="rejected")
        )
        print(json.dumps(response, separators=(",", ":")))
        return 77
    try:
        payload = _read_request()
        registry = load_registry()
        response = execute_request(payload, registry)
    except HelperFailure as error:
        print(json.dumps(_failure_payload(error), separators=(",", ":")))
        return 1
    except Exception:
        response = _failure_payload(
            HelperFailure("internal_error", "Action helper failed safely.")
        )
        print(json.dumps(response, separators=(",", ":")))
        return 1
    print(json.dumps(response, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
