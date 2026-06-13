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


def _parse_bool(raw_value: str | None, default: bool) -> bool:
    if raw_value is None:
        return default
    return raw_value.strip().lower() in {"1", "true", "yes", "on"}


def _parse_int(raw_value: str | None, default: int, *, minimum: int = 0) -> int:
    if raw_value is None:
        return default
    try:
        parsed = int(raw_value.strip())
    except ValueError:
        return default
    return max(minimum, parsed)


def _parse_float(raw_value: str | None, default: float, *, minimum: float = 0.0) -> float:
    if raw_value is None:
        return default
    try:
        parsed = float(raw_value.strip())
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
    disk_mountpoint: str
    log_level: str
    host: str
    port: int
    reload: bool
    docker_timeout_seconds: int
    history_enabled: bool
    history_db_path: Path
    history_sample_interval_seconds: int
    history_retention_days: int
    history_retention_cleanup_interval_seconds: int
    history_max_response_points: int
    alerts_enabled: bool
    alert_poll_interval_seconds: int
    alert_grace_seconds: int
    alert_db_path: Path
    cpu_alert_threshold: float
    memory_alert_threshold: float
    disk_alert_threshold: float
    gpu_usage_alert_threshold: float
    gpu_temp_alert_threshold: float
    mobile_push_enabled: bool
    mobile_push_include_recovery: bool
    mobile_push_retry_initial_seconds: int
    mobile_push_retry_max_seconds: int
    firebase_service_account_file: Path
    mobile_alert_api_token: str | None
    alert_consumer_api_token: str | None


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    host = os.getenv("HOST", "0.0.0.0")
    default_origins = list(DEFAULT_ORIGINS)

    return Settings(
        app_name=os.getenv("APP_NAME", "Linux Server monitoring tool"),
        app_version=os.getenv("APP_VERSION", "0.2.0"),
        api_prefix=os.getenv("API_PREFIX", "/api"),
        cors_origins=_parse_origins(os.getenv("CORS_ORIGINS"), default_origins),
        cors_origin_regex=_parse_optional_string(os.getenv("CORS_ORIGIN_REGEX")),
        disk_mountpoint=os.getenv("DISK_MOUNTPOINT", "/"),
        log_level=os.getenv("LOG_LEVEL", "INFO"),
        host=host,
        port=_parse_int(os.getenv("PORT"), 4040, minimum=1),
        reload=_parse_bool(os.getenv("RELOAD"), default=False),
        docker_timeout_seconds=_parse_int(os.getenv("DOCKER_TIMEOUT_SECONDS"), 3, minimum=1),
        history_enabled=_parse_bool(os.getenv("HISTORY_ENABLED"), default=True),
        history_db_path=Path(
            os.getenv(
                "HISTORY_DB_PATH",
                "/var/lib/linux-monitoring/history.sqlite3",
            )
        ),
        history_sample_interval_seconds=_parse_int(
            os.getenv("HISTORY_SAMPLE_INTERVAL_SECONDS"),
            60,
            minimum=5,
        ),
        history_retention_days=_parse_int(
            os.getenv("HISTORY_RETENTION_DAYS"),
            30,
            minimum=1,
        ),
        history_retention_cleanup_interval_seconds=_parse_int(
            os.getenv("HISTORY_RETENTION_CLEANUP_INTERVAL_SECONDS"),
            3600,
            minimum=60,
        ),
        history_max_response_points=_parse_int(
            os.getenv("HISTORY_MAX_RESPONSE_POINTS"),
            720,
            minimum=60,
        ),
        alerts_enabled=_parse_bool(os.getenv("ALERTS_ENABLED"), default=True),
        alert_poll_interval_seconds=_parse_int(
            os.getenv("ALERT_POLL_INTERVAL_SECONDS"),
            30,
            minimum=5,
        ),
        alert_grace_seconds=_parse_int(
            os.getenv("ALERT_GRACE_SECONDS"),
            300,
            minimum=0,
        ),
        alert_db_path=Path(
            os.getenv(
                "ALERT_DB_PATH",
                "/var/lib/linux-monitoring/alerts.sqlite3",
            )
        ),
        cpu_alert_threshold=_parse_float(
            os.getenv("CPU_ALERT_THRESHOLD"),
            85.0,
            minimum=0.0,
        ),
        memory_alert_threshold=_parse_float(
            os.getenv("MEMORY_ALERT_THRESHOLD"),
            90.0,
            minimum=0.0,
        ),
        disk_alert_threshold=_parse_float(
            os.getenv("DISK_ALERT_THRESHOLD"),
            90.0,
            minimum=0.0,
        ),
        gpu_usage_alert_threshold=_parse_float(
            os.getenv("GPU_USAGE_ALERT_THRESHOLD"),
            85.0,
            minimum=0.0,
        ),
        gpu_temp_alert_threshold=_parse_float(
            os.getenv("GPU_TEMP_ALERT_THRESHOLD"),
            80.0,
            minimum=1.0,
        ),
        mobile_push_enabled=_parse_bool(os.getenv("MOBILE_PUSH_ENABLED"), default=False),
        mobile_push_include_recovery=_parse_bool(
            os.getenv("MOBILE_PUSH_INCLUDE_RECOVERY"),
            default=True,
        ),
        mobile_push_retry_initial_seconds=_parse_int(
            os.getenv("MOBILE_PUSH_RETRY_INITIAL_SECONDS"),
            30,
            minimum=1,
        ),
        mobile_push_retry_max_seconds=_parse_int(
            os.getenv("MOBILE_PUSH_RETRY_MAX_SECONDS"),
            900,
            minimum=1,
        ),
        firebase_service_account_file=Path(
            os.getenv(
                "FIREBASE_SERVICE_ACCOUNT_FILE",
                "/etc/linux-monitor-mobile-alerts/firebase-service-account.json",
            )
        ),
        mobile_alert_api_token=_parse_optional_string(os.getenv("MOBILE_ALERT_API_TOKEN")),
        alert_consumer_api_token=_parse_optional_string(
            os.getenv("ALERT_CONSUMER_API_TOKEN")
        ),
    )
