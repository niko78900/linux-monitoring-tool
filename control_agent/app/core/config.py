from __future__ import annotations

import os
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path

from dotenv import load_dotenv

BASE_DIR = Path(__file__).resolve().parents[2]
load_dotenv(BASE_DIR / ".env")

DEFAULT_ORIGINS = [
    "http://localhost:4041",
    "http://127.0.0.1:4041",
]


def _parse_origins(raw_origins: str | None, default_origins: list[str]) -> list[str]:
    if not raw_origins:
        return default_origins
    origins = [origin.strip() for origin in raw_origins.split(",") if origin.strip()]
    return origins or default_origins


def _parse_int(raw_value: str | None, default: int, *, minimum: int = 0) -> int:
    if raw_value is None:
        return default
    try:
        parsed = int(raw_value.strip())
    except ValueError:
        return default
    return max(minimum, parsed)


def _parse_optional_string(raw_value: str | None) -> str | None:
    if raw_value is None:
        return None
    normalized = raw_value.strip()
    return normalized or None


@dataclass(frozen=True)
class Settings:
    app_name: str
    app_version: str
    api_prefix: str
    cors_origins: list[str]
    cors_origin_regex: str | None
    log_level: str
    host: str
    port: int
    control_api_token: str | None
    known_devices_config_path: Path
    managed_hosts_config_path: Path
    services_config_path: Path
    service_control_helper_path: Path
    service_command_timeout_seconds: int
    mobile_push_token_registry_file: Path
    firebase_service_account_file: Path
    main_pc_mac: str
    wake_broadcast_host: str
    wake_port: int
    wake_rate_limit_seconds: int


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings(
        app_name=os.getenv("APP_NAME", "Homelab Control Agent"),
        app_version=os.getenv("APP_VERSION", "0.1.0"),
        api_prefix=os.getenv("API_PREFIX", "/api"),
        cors_origins=_parse_origins(os.getenv("CORS_ORIGINS"), list(DEFAULT_ORIGINS)),
        cors_origin_regex=_parse_optional_string(os.getenv("CORS_ORIGIN_REGEX")),
        log_level=os.getenv("LOG_LEVEL", "INFO"),
        host=os.getenv("HOST", "127.0.0.1"),
        port=_parse_int(os.getenv("PORT"), 4042, minimum=1),
        control_api_token=_parse_optional_string(os.getenv("CONTROL_API_TOKEN")),
        known_devices_config_path=Path(
            os.getenv(
                "KNOWN_DEVICES_CONFIG_PATH",
                str(BASE_DIR / "config" / "known_devices.example.yaml"),
            )
        ),
        managed_hosts_config_path=Path(
            os.getenv(
                "MANAGED_HOSTS_CONFIG_PATH",
                str(BASE_DIR / "config" / "managed_hosts.example.yaml"),
            )
        ),
        services_config_path=Path(
            os.getenv(
                "SERVICES_CONFIG_PATH",
                str(BASE_DIR / "config" / "services.example.yaml"),
            )
        ),
        service_control_helper_path=Path(
            os.getenv(
                "SERVICE_CONTROL_HELPER_PATH",
                "/usr/local/sbin/homelab-service-control",
            )
        ),
        service_command_timeout_seconds=_parse_int(
            os.getenv("SERVICE_COMMAND_TIMEOUT_SECONDS"), 5, minimum=1
        ),
        mobile_push_token_registry_file=Path(
            os.getenv(
                "MOBILE_PUSH_TOKEN_REGISTRY_FILE",
                "/var/lib/linux-monitoring/mobile_push_tokens.json",
            )
        ),
        firebase_service_account_file=Path(
            os.getenv(
                "FIREBASE_SERVICE_ACCOUNT_FILE",
                "/etc/linux-monitor-mobile-alerts/firebase-service-account.json",
            )
        ),
        main_pc_mac=os.getenv("MAIN_PC_MAC", "AA:BB:CC:DD:EE:FF").strip(),
        wake_broadcast_host=os.getenv("WAKE_BROADCAST_HOST", "255.255.255.255").strip(),
        wake_port=_parse_int(os.getenv("WAKE_PORT"), 9, minimum=1),
        wake_rate_limit_seconds=_parse_int(
            os.getenv("WAKE_RATE_LIMIT_SECONDS"), 30, minimum=1
        ),
    )
