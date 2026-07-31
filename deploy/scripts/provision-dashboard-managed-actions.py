#!/var/lib/homelab-venvs/linux-monitor-control-agent/bin/python
from __future__ import annotations

import argparse
import ipaddress
import json
import os
import re
import stat
import subprocess
import tempfile
from pathlib import Path
from urllib import request as url_request
from urllib.parse import urlsplit

import yaml
from dotenv import dotenv_values

ID_PATTERN = re.compile(r"^[a-z0-9](?:[a-z0-9-]{0,62}[a-z0-9])?$")
TARGET_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.@-]{0,127}$")
MAC_PATTERN = re.compile(r"^(?:[0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}$")
DESTINATION = Path("/etc/linux-monitor/dashboard-managed-actions.yml")
CONTROL_ENV = Path("/etc/linux-monitor/control-agent.env")
DOCKER_BINARY = "/usr/bin/docker"
IP_BINARY = "/usr/sbin/ip"


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Provision one verified container action and the existing Main PC wake target.",
    )
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--service-id", required=True)
    parser.add_argument("--service-name", required=True)
    parser.add_argument("--container-name", required=True)
    parser.add_argument("--compose-project", required=True)
    parser.add_argument("--compose-service", required=True)
    parser.add_argument("--health-url", required=True)
    return parser.parse_args()


def strict_target(value: str, *, identifier: bool = False) -> str:
    pattern = ID_PATTERN if identifier else TARGET_PATTERN
    if not pattern.fullmatch(value):
        raise SystemExit("service identity contains invalid characters")
    return value


def validate_protected_file(path: Path, *, maximum_mode: int = 0o640) -> None:
    metadata = path.lstat()
    if (
        not stat.S_ISREG(metadata.st_mode)
        or metadata.st_uid != 0
        or stat.S_IMODE(metadata.st_mode) & ~maximum_mode
    ):
        raise SystemExit(f"protected source metadata is unsafe: {path}")


def docker_field(container: str, template: str) -> str:
    result = subprocess.run(
        [DOCKER_BINARY, "inspect", "--format", template, container],
        check=False,
        capture_output=True,
        text=True,
        timeout=5,
    )
    value = result.stdout.strip()
    if result.returncode != 0 or not value or "\n" in value or len(value) > 128:
        raise SystemExit("container identity could not be validated")
    return value


def main() -> int:
    args = parse_arguments()
    if os.geteuid() != 0:
        raise SystemExit("provisioning must run as root")

    service_id = strict_target(args.service_id, identifier=True)
    container_name = strict_target(args.container_name)
    compose_project = strict_target(args.compose_project)
    compose_service = strict_target(args.compose_service)
    service_name = args.service_name.strip()
    if not service_name or len(service_name) > 80:
        raise SystemExit("service name is invalid")

    parsed_health = urlsplit(args.health_url)
    if (
        parsed_health.scheme != "http"
        or parsed_health.hostname not in {"127.0.0.1", "localhost"}
        or parsed_health.port is None
        or parsed_health.username
        or parsed_health.password
    ):
        raise SystemExit("health URL must be an explicit loopback HTTP URL")

    validate_protected_file(CONTROL_ENV)
    values = dotenv_values(CONTROL_ENV)
    raw_mac_address = str(values.get("MAIN_PC_MAC") or "").strip()
    broadcast_address = str(values.get("WAKE_BROADCAST_HOST") or "").strip()
    wake_port = int(str(values.get("WAKE_PORT") or "9"))
    if not MAC_PATTERN.fullmatch(raw_mac_address) or not 1 <= wake_port <= 65535:
        raise SystemExit("existing Wake-on-LAN configuration is invalid")
    mac_address = ":".join(
        raw_mac_address.replace("-", ":").upper().split(":")
    )
    try:
        broadcast = ipaddress.IPv4Address(broadcast_address)
    except (ipaddress.AddressValueError, TypeError) as error:
        raise SystemExit("existing wake broadcast is invalid") from error
    if broadcast.is_loopback or broadcast.is_multicast or broadcast.is_unspecified:
        raise SystemExit("existing wake broadcast is invalid")

    known_devices_path = Path(str(values.get("KNOWN_DEVICES_CONFIG_PATH") or ""))
    if not known_devices_path.is_absolute():
        raise SystemExit("known-device configuration path is invalid")
    validate_protected_file(known_devices_path)
    known_devices = yaml.safe_load(known_devices_path.read_text(encoding="utf-8")) or {}
    main_pc = next(
        (
            item
            for item in known_devices.get("devices", [])
            if isinstance(item, dict) and item.get("id") == "main-pc"
        ),
        None,
    )
    if main_pc is None or not main_pc.get("wol_enabled"):
        raise SystemExit("the existing Main PC wake target is unavailable")
    try:
        main_pc_address = ipaddress.IPv4Address(str(main_pc.get("lan_ip") or ""))
    except ipaddress.AddressValueError as error:
        raise SystemExit("existing Main PC address is invalid") from error
    route = json.loads(
        subprocess.run(
            [IP_BINARY, "-j", "route", "get", str(main_pc_address)],
            check=True,
            capture_output=True,
            text=True,
            timeout=5,
        ).stdout
    )
    interface = route[0].get("dev")
    if not isinstance(interface, str) or not TARGET_PATTERN.fullmatch(interface):
        raise SystemExit("wake interface could not be resolved")
    addresses = json.loads(
        subprocess.run(
            [IP_BINARY, "-j", "address", "show", "dev", interface],
            check=True,
            capture_output=True,
            text=True,
            timeout=5,
        ).stdout
    )
    broadcasts = {
        item["broadcast"]
        for link in addresses
        for item in link.get("addr_info", [])
        if item.get("family") == "inet" and item.get("broadcast")
    }
    if str(broadcast) != "255.255.255.255" and str(broadcast) not in broadcasts:
        raise SystemExit("wake broadcast does not belong to the resolved interface")

    if docker_field(container_name, '{{index .Config.Labels "com.docker.compose.project"}}') != compose_project:
        raise SystemExit("container Compose project does not match")
    if docker_field(container_name, '{{index .Config.Labels "com.docker.compose.service"}}') != compose_service:
        raise SystemExit("container Compose service does not match")
    if docker_field(container_name, "{{.State.Status}}") != "running":
        raise SystemExit("container must be running during provisioning")
    with url_request.urlopen(args.health_url, timeout=5) as response:
        if not 200 <= response.status < 400:
            raise SystemExit("container health endpoint is not healthy")

    document = {
        "services": [
            {
                "id": service_id,
                "name": service_name,
                "kind": "docker_container",
                "container_name": container_name,
                "expected_compose_project": compose_project,
                "expected_compose_service": compose_service,
                "allowed_actions": ["start", "stop", "restart"],
                "timeout_seconds": 90,
                "health_url": args.health_url,
                "confirmation_level": "normal",
            }
        ],
        "wake_targets": [
            {
                "id": "main-pc",
                "name": "Main PC",
                "allowed_actions": ["wake"],
                "mac_address": mac_address,
                "broadcast_address": str(broadcast),
                "interface": interface,
                "port": wake_port,
                "timeout_seconds": 10,
                "confirmation_level": "normal",
            }
        ],
    }

    if args.check:
        print("managed action registry inputs validated")
        return 0
    if DESTINATION.exists():
        raise SystemExit(f"refusing to overwrite existing {DESTINATION}")
    destination_directory = DESTINATION.parent
    metadata = destination_directory.stat()
    if metadata.st_uid != 0 or metadata.st_gid != 0 or stat.S_IMODE(metadata.st_mode) & 0o022:
        raise SystemExit("protected configuration directory permissions are unsafe")

    descriptor, temporary_name = tempfile.mkstemp(
        prefix=".dashboard-managed-actions.",
        dir=destination_directory,
    )
    temporary_path = Path(temporary_name)
    try:
        os.fchmod(descriptor, 0o600)
        os.fchown(descriptor, 0, 0)
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            yaml.safe_dump(document, handle, sort_keys=False)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary_path, DESTINATION)
    finally:
        temporary_path.unlink(missing_ok=True)
    print(f"installed protected managed action registry at {DESTINATION}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
