from __future__ import annotations

import os
from dataclasses import dataclass
from functools import lru_cache
from ipaddress import IPv4Network, IPv6Network, ip_network
from pathlib import Path

AllowedNetwork = IPv4Network | IPv6Network


def _parse_allowed_networks(raw_value: str | None) -> tuple[AllowedNetwork, ...]:
    if not raw_value:
        return ()

    networks: list[AllowedNetwork] = []
    for raw_network in raw_value.split(","):
        candidate = raw_network.strip()
        if not candidate:
            continue
        try:
            networks.append(ip_network(candidate, strict=False))
        except ValueError as error:
            raise ValueError(
                "DASHBOARD_CONTROL_ACTION_ALLOWED_NETWORKS contains an invalid network"
            ) from error
    return tuple(networks)


def _parse_bounded_int(
    name: str,
    raw_value: str | None,
    default: int,
    *,
    minimum: int,
    maximum: int,
) -> int:
    if raw_value is None:
        return default
    try:
        value = int(raw_value.strip())
    except (AttributeError, ValueError) as error:
        raise ValueError(f"{name} must be an integer") from error
    if not minimum <= value <= maximum:
        raise ValueError(f"{name} is outside its permitted range")
    return value


def _registry_path() -> Path:
    configured = os.getenv("DASHBOARD_ACTION_REGISTRY_PATH")
    if configured:
        return Path(configured)
    credentials_directory = os.getenv("CREDENTIALS_DIRECTORY")
    if credentials_directory:
        return Path(credentials_directory) / "dashboard-managed-actions.yml"
    return Path("/etc/linux-monitor/dashboard-managed-actions.yml")


@dataclass(frozen=True)
class ActionServiceSettings:
    token: str | None
    allowed_networks: tuple[AllowedNetwork, ...]
    registry_path: Path
    database_path: Path
    helper_path: Path
    worker_count: int
    queue_size: int
    retention_records: int
    retention_days: int

    def validate_for_startup(self, *, require_helper: bool = True) -> None:
        if self.token is None or len(self.token) < 32:
            raise RuntimeError(
                "DASHBOARD_CONTROL_ACTION_TOKEN must contain at least 32 characters"
            )
        if not self.allowed_networks:
            raise RuntimeError(
                "DASHBOARD_CONTROL_ACTION_ALLOWED_NETWORKS must contain a network"
            )
        for label, path in (
            ("registry", self.registry_path),
            ("database", self.database_path),
            ("helper", self.helper_path),
        ):
            if not path.is_absolute():
                raise RuntimeError(f"Dashboard action {label} path must be absolute")
        if require_helper and (
            not self.helper_path.is_file()
            or not os.access(self.helper_path, os.X_OK)
        ):
            raise RuntimeError("Dashboard action helper is unavailable")


@lru_cache(maxsize=1)
def get_action_service_settings() -> ActionServiceSettings:
    raw_token = os.getenv("DASHBOARD_CONTROL_ACTION_TOKEN")
    token = raw_token.strip() if raw_token and raw_token.strip() else None
    return ActionServiceSettings(
        token=token,
        allowed_networks=_parse_allowed_networks(
            os.getenv("DASHBOARD_CONTROL_ACTION_ALLOWED_NETWORKS")
        ),
        registry_path=_registry_path(),
        database_path=Path(
            os.getenv(
                "DASHBOARD_ACTION_DB_PATH",
                "/var/lib/linux-monitor/dashboard-actions/dashboard-actions.db",
            )
        ),
        helper_path=Path(
            os.getenv(
                "DASHBOARD_ACTION_HELPER_PATH",
                "/usr/local/libexec/linux-monitor-dashboard-action-helper",
            )
        ),
        worker_count=_parse_bounded_int(
            "DASHBOARD_ACTION_WORKERS",
            os.getenv("DASHBOARD_ACTION_WORKERS"),
            1,
            minimum=1,
            maximum=4,
        ),
        queue_size=_parse_bounded_int(
            "DASHBOARD_ACTION_QUEUE_SIZE",
            os.getenv("DASHBOARD_ACTION_QUEUE_SIZE"),
            32,
            minimum=1,
            maximum=100,
        ),
        retention_records=_parse_bounded_int(
            "DASHBOARD_ACTION_RETENTION_RECORDS",
            os.getenv("DASHBOARD_ACTION_RETENTION_RECORDS"),
            1000,
            minimum=10,
            maximum=10000,
        ),
        retention_days=_parse_bounded_int(
            "DASHBOARD_ACTION_RETENTION_DAYS",
            os.getenv("DASHBOARD_ACTION_RETENTION_DAYS"),
            90,
            minimum=1,
            maximum=3650,
        ),
    )
