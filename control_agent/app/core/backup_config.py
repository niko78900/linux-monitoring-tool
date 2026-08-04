from __future__ import annotations

import os
from dataclasses import dataclass
from functools import lru_cache
from ipaddress import IPv4Network, IPv6Network, ip_network
from pathlib import Path

AllowedNetwork = IPv4Network | IPv6Network


def _parse_networks(raw_value: str | None) -> tuple[AllowedNetwork, ...]:
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
            raise ValueError("DASHBOARD_BACKUP_ALLOWED_NETWORKS is invalid") from error
    return tuple(networks)


def _bounded_int(
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
        value = int(raw_value)
    except (TypeError, ValueError) as error:
        raise ValueError(f"{name} must be an integer") from error
    if not minimum <= value <= maximum:
        raise ValueError(f"{name} is outside its permitted range")
    return value


def _registry_path() -> tuple[Path, bool]:
    configured = os.getenv("DASHBOARD_BACKUP_REGISTRY_PATH")
    if configured:
        return Path(configured), False
    credentials_directory = os.getenv("CREDENTIALS_DIRECTORY")
    if credentials_directory:
        return Path(credentials_directory) / "dashboard-backups.yml", True
    return Path("/etc/linux-monitor/dashboard-backups.yml"), False


@dataclass(frozen=True)
class BackupServiceSettings:
    token: str | None
    allowed_networks: tuple[AllowedNetwork, ...]
    registry_path: Path
    registry_is_credential: bool
    database_path: Path
    helper_path: Path
    worker_count: int
    queue_size: int
    retention_records: int
    retention_days: int
    assessment_refresh_seconds: int = 900
    assessment_max_age_seconds: int = 3600
    assessment_timeout_seconds: int = 300
    assessment_concurrency: int = 2

    def validate_for_startup(self, *, require_helper: bool = True) -> None:
        if self.token is None or len(self.token) < 32:
            raise RuntimeError("DASHBOARD_BACKUP_TOKEN must contain at least 32 characters")
        if not self.allowed_networks:
            raise RuntimeError("DASHBOARD_BACKUP_ALLOWED_NETWORKS must contain a network")
        for label, path in (
            ("registry", self.registry_path),
            ("database", self.database_path),
            ("helper", self.helper_path),
        ):
            if not path.is_absolute():
                raise RuntimeError(f"Dashboard backup {label} path must be absolute")
        if require_helper and (
            not self.helper_path.is_file() or not os.access(self.helper_path, os.X_OK)
        ):
            raise RuntimeError("Dashboard backup helper is unavailable")
        if self.assessment_max_age_seconds < self.assessment_refresh_seconds:
            raise RuntimeError(
                "DASHBOARD_BACKUP_ASSESSMENT_MAX_AGE_SECONDS must be greater than or "
                "equal to DASHBOARD_BACKUP_ASSESSMENT_REFRESH_SECONDS"
            )


@lru_cache(maxsize=1)
def get_backup_service_settings() -> BackupServiceSettings:
    token_value = os.getenv("DASHBOARD_BACKUP_TOKEN")
    token = token_value.strip() if token_value and token_value.strip() else None
    registry_path, registry_is_credential = _registry_path()
    return BackupServiceSettings(
        token=token,
        allowed_networks=_parse_networks(os.getenv("DASHBOARD_BACKUP_ALLOWED_NETWORKS")),
        registry_path=registry_path,
        registry_is_credential=registry_is_credential,
        database_path=Path(
            os.getenv(
                "DASHBOARD_BACKUP_DB_PATH",
                "/var/lib/linux-monitor/dashboard-backups/dashboard-backups.db",
            )
        ),
        helper_path=Path(
            os.getenv(
                "DASHBOARD_BACKUP_HELPER_PATH",
                "/usr/local/libexec/linux-monitor-dashboard-backup-helper",
            )
        ),
        worker_count=_bounded_int(
            "DASHBOARD_BACKUP_WORKERS",
            os.getenv("DASHBOARD_BACKUP_WORKERS"),
            1,
            minimum=1,
            maximum=2,
        ),
        queue_size=_bounded_int(
            "DASHBOARD_BACKUP_QUEUE_SIZE",
            os.getenv("DASHBOARD_BACKUP_QUEUE_SIZE"),
            16,
            minimum=1,
            maximum=100,
        ),
        retention_records=_bounded_int(
            "DASHBOARD_BACKUP_HISTORY_RECORDS",
            os.getenv("DASHBOARD_BACKUP_HISTORY_RECORDS"),
            5000,
            minimum=10,
            maximum=50_000,
        ),
        retention_days=_bounded_int(
            "DASHBOARD_BACKUP_HISTORY_DAYS",
            os.getenv("DASHBOARD_BACKUP_HISTORY_DAYS"),
            365,
            minimum=1,
            maximum=3650,
        ),
        assessment_refresh_seconds=_bounded_int(
            "DASHBOARD_BACKUP_ASSESSMENT_REFRESH_SECONDS",
            os.getenv("DASHBOARD_BACKUP_ASSESSMENT_REFRESH_SECONDS"),
            900,
            minimum=60,
            maximum=86_400,
        ),
        assessment_max_age_seconds=_bounded_int(
            "DASHBOARD_BACKUP_ASSESSMENT_MAX_AGE_SECONDS",
            os.getenv("DASHBOARD_BACKUP_ASSESSMENT_MAX_AGE_SECONDS"),
            3600,
            minimum=60,
            maximum=604_800,
        ),
        assessment_timeout_seconds=_bounded_int(
            "DASHBOARD_BACKUP_ASSESSMENT_TIMEOUT_SECONDS",
            os.getenv("DASHBOARD_BACKUP_ASSESSMENT_TIMEOUT_SECONDS"),
            300,
            minimum=10,
            maximum=600,
        ),
        assessment_concurrency=_bounded_int(
            "DASHBOARD_BACKUP_ASSESSMENT_CONCURRENCY",
            os.getenv("DASHBOARD_BACKUP_ASSESSMENT_CONCURRENCY"),
            2,
            minimum=1,
            maximum=4,
        ),
    )
