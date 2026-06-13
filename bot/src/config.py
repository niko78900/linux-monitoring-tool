from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path
from typing import Mapping

from dotenv import load_dotenv

_ENV_FILE = Path(__file__).resolve().parents[1] / ".env"
_BOT_DIR = Path(__file__).resolve().parents[1]
_DEFAULT_STATUS_SCHEDULE_STATE_FILE = _BOT_DIR / "status_schedule_state.json"
_DEFAULT_ALERT_STATE_FILE = _BOT_DIR / "alert_state.json"
_DEFAULT_MOBILE_PUSH_OUTBOX_FILE = _BOT_DIR / "mobile_push_delivery_state.json"


@dataclass(frozen=True)
class BotConfig:
    discord_bot_token: str
    discord_guild_id: int | None
    discord_channel_id: int
    monitor_api_base_url: str
    poll_interval_seconds: int
    cpu_alert_threshold: float
    memory_alert_threshold: float
    disk_alert_threshold: float
    gpu_temp_alert_threshold: float
    gpu_usage_alert_threshold: float
    enable_docker_alerts: bool
    enable_raid_alerts: bool
    alert_grace_seconds: int
    mobile_push_enabled: bool
    mobile_push_include_recovery: bool
    mobile_push_token_registry_file: str
    mobile_push_outbox_file: str
    mobile_push_retry_initial_seconds: int
    mobile_push_retry_max_seconds: int
    firebase_service_account_file: str
    status_schedule_state_file: str
    alert_state_file: str
    request_timeout_seconds: float = 8.0

    @classmethod
    def from_env(cls, env: Mapping[str, str] | None = None) -> BotConfig:
        source = env
        if source is None:
            load_dotenv(_ENV_FILE)
            source = os.environ

        discord_bot_token = _require_str(source, "DISCORD_BOT_TOKEN")
        discord_guild_id = _parse_optional_int(source, "DISCORD_GUILD_ID")
        discord_channel_id = _parse_int(source, "DISCORD_CHANNEL_ID")
        monitor_api_base_url = _require_str(source, "MONITOR_API_BASE_URL").rstrip("/")
        poll_interval_seconds = _parse_int(source, "POLL_INTERVAL_SECONDS", default=30, minimum=5)
        cpu_alert_threshold = _parse_percent(source, "CPU_ALERT_THRESHOLD", default=85.0)
        memory_alert_threshold = _parse_percent(source, "MEMORY_ALERT_THRESHOLD", default=90.0)
        disk_alert_threshold = _parse_percent(source, "DISK_ALERT_THRESHOLD", default=90.0)
        gpu_temp_alert_threshold = _parse_float(source, "GPU_TEMP_ALERT_THRESHOLD", default=80.0, minimum=1.0)
        gpu_usage_alert_threshold = _parse_percent(source, "GPU_USAGE_ALERT_THRESHOLD", default=85.0)
        enable_docker_alerts = _parse_bool(source, "ENABLE_DOCKER_ALERTS", default=True)
        enable_raid_alerts = _parse_bool(source, "ENABLE_RAID_ALERTS", default=True)
        alert_grace_seconds = _parse_alert_grace_seconds(source)
        mobile_push_enabled = _parse_bool(source, "MOBILE_PUSH_ENABLED", default=False)
        mobile_push_include_recovery = _parse_bool(source, "MOBILE_PUSH_INCLUDE_RECOVERY", default=True)
        mobile_push_token_registry_file = _parse_path(
            source,
            "MOBILE_PUSH_TOKEN_REGISTRY_FILE",
            "/var/lib/linux-monitoring/mobile_push_tokens.json",
        )
        mobile_push_outbox_file = _parse_path(
            source,
            "MOBILE_PUSH_OUTBOX_FILE",
            "/var/lib/linux-monitoring/mobile_push_delivery_state.json",
        )
        mobile_push_retry_initial_seconds = _parse_int(
            source,
            "MOBILE_PUSH_RETRY_INITIAL_SECONDS",
            default=30,
            minimum=1,
        )
        mobile_push_retry_max_seconds = _parse_int(
            source,
            "MOBILE_PUSH_RETRY_MAX_SECONDS",
            default=900,
            minimum=1,
        )
        firebase_service_account_file = _parse_path(
            source,
            "FIREBASE_SERVICE_ACCOUNT_FILE",
            "/etc/linux-monitor-mobile-alerts/firebase-service-account.json",
        )
        status_schedule_state_file = _parse_status_schedule_state_file(source)
        alert_state_file = _parse_alert_state_file(source)

        return cls(
            discord_bot_token=discord_bot_token,
            discord_guild_id=discord_guild_id,
            discord_channel_id=discord_channel_id,
            monitor_api_base_url=monitor_api_base_url,
            poll_interval_seconds=poll_interval_seconds,
            cpu_alert_threshold=cpu_alert_threshold,
            memory_alert_threshold=memory_alert_threshold,
            disk_alert_threshold=disk_alert_threshold,
            gpu_temp_alert_threshold=gpu_temp_alert_threshold,
            gpu_usage_alert_threshold=gpu_usage_alert_threshold,
            enable_docker_alerts=enable_docker_alerts,
            enable_raid_alerts=enable_raid_alerts,
            alert_grace_seconds=alert_grace_seconds,
            mobile_push_enabled=mobile_push_enabled,
            mobile_push_include_recovery=mobile_push_include_recovery,
            mobile_push_token_registry_file=mobile_push_token_registry_file,
            mobile_push_outbox_file=mobile_push_outbox_file,
            mobile_push_retry_initial_seconds=mobile_push_retry_initial_seconds,
            mobile_push_retry_max_seconds=mobile_push_retry_max_seconds,
            firebase_service_account_file=firebase_service_account_file,
            status_schedule_state_file=status_schedule_state_file,
            alert_state_file=alert_state_file,
        )


def _get_raw(source: Mapping[str, str], name: str) -> str | None:
    value = source.get(name)
    if value is None:
        return None
    normalized = value.strip()
    return normalized if normalized else None


def _require_str(source: Mapping[str, str], name: str) -> str:
    value = _get_raw(source, name)
    if value is None:
        raise ValueError(f"{name} is required.")
    return value


def _parse_optional_int(source: Mapping[str, str], name: str) -> int | None:
    value = _get_raw(source, name)
    if value is None:
        return None
    try:
        parsed = int(value)
    except ValueError as exc:
        raise ValueError(f"{name} must be an integer.") from exc
    if parsed <= 0:
        raise ValueError(f"{name} must be a positive integer.")
    return parsed


def _parse_int(source: Mapping[str, str], name: str, default: int | None = None, minimum: int = 1) -> int:
    value = _get_raw(source, name)
    if value is None:
        if default is None:
            raise ValueError(f"{name} is required.")
        return default
    try:
        parsed = int(value)
    except ValueError as exc:
        raise ValueError(f"{name} must be an integer.") from exc
    if parsed < minimum:
        raise ValueError(f"{name} must be >= {minimum}.")
    return parsed


def _parse_float(source: Mapping[str, str], name: str, default: float | None = None, minimum: float = 0.0) -> float:
    value = _get_raw(source, name)
    if value is None:
        if default is None:
            raise ValueError(f"{name} is required.")
        return default
    try:
        parsed = float(value)
    except ValueError as exc:
        raise ValueError(f"{name} must be a number.") from exc
    if parsed < minimum:
        raise ValueError(f"{name} must be >= {minimum}.")
    return parsed


def _parse_percent(source: Mapping[str, str], name: str, default: float) -> float:
    value = _parse_float(source, name, default=default, minimum=0.0)
    if value > 100.0:
        raise ValueError(f"{name} must be <= 100.")
    return value


def _parse_bool(source: Mapping[str, str], name: str, default: bool) -> bool:
    value = _get_raw(source, name)
    if value is None:
        return default
    normalized = value.lower()
    if normalized in {"1", "true", "yes", "on"}:
        return True
    if normalized in {"0", "false", "no", "off"}:
        return False
    raise ValueError(f"{name} must be a boolean value (true/false).")


def _parse_status_schedule_state_file(source: Mapping[str, str]) -> str:
    raw_value = _get_raw(source, "STATUS_SCHEDULE_STATE_FILE")
    if raw_value is None:
        return str(_DEFAULT_STATUS_SCHEDULE_STATE_FILE)

    path = Path(raw_value).expanduser()
    if not path.is_absolute():
        path = _BOT_DIR / path
    return str(path)


def _parse_alert_state_file(source: Mapping[str, str]) -> str:
    raw_value = _get_raw(source, "ALERT_STATE_FILE")
    if raw_value is None:
        return str(_DEFAULT_ALERT_STATE_FILE)

    path = Path(raw_value).expanduser()
    if not path.is_absolute():
        path = _BOT_DIR / path
    return str(path)


def _parse_path(source: Mapping[str, str], name: str, default: str) -> str:
    raw_value = _get_raw(source, name)
    if raw_value is None:
        return default
    return str(Path(raw_value).expanduser())


def _parse_alert_grace_seconds(source: Mapping[str, str]) -> int:
    # ALERT_GRACE_SECONDS applies to all alert keys.
    # ENDPOINT_ALERT_GRACE_SECONDS is kept as a backward-compatible fallback.
    raw_new = _get_raw(source, "ALERT_GRACE_SECONDS")
    if raw_new is not None:
        return _parse_int(source, "ALERT_GRACE_SECONDS", minimum=0)
    return _parse_int(source, "ENDPOINT_ALERT_GRACE_SECONDS", default=300, minimum=0)
