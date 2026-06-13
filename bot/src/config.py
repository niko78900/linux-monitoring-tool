from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path
from typing import Mapping

from dotenv import load_dotenv

_ENV_FILE = Path(__file__).resolve().parents[1] / ".env"
_BOT_DIR = Path(__file__).resolve().parents[1]
_DEFAULT_STATUS_SCHEDULE_STATE_FILE = _BOT_DIR / "status_schedule_state.json"
_DEFAULT_ALERT_CURSOR_FILE = _BOT_DIR / "discord_alert_cursor.json"


@dataclass(frozen=True)
class BotConfig:
    discord_bot_token: str
    discord_guild_id: int | None
    discord_channel_id: int
    monitor_api_base_url: str
    poll_interval_seconds: int
    alert_consumer_api_token: str
    discord_alert_cursor_file: str
    discord_alert_replay_on_first_start: bool
    status_schedule_state_file: str
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
        monitor_api_base_url = _parse_monitoring_api_base_url(source)
        poll_interval_seconds = _parse_int(source, "POLL_INTERVAL_SECONDS", default=30, minimum=5)
        alert_consumer_api_token = _require_str(source, "ALERT_CONSUMER_API_TOKEN")
        discord_alert_cursor_file = _parse_alert_cursor_file(source)
        discord_alert_replay_on_first_start = _parse_bool(
            source,
            "DISCORD_ALERT_REPLAY_ON_FIRST_START",
            default=False,
        )
        status_schedule_state_file = _parse_status_schedule_state_file(source)

        return cls(
            discord_bot_token=discord_bot_token,
            discord_guild_id=discord_guild_id,
            discord_channel_id=discord_channel_id,
            monitor_api_base_url=monitor_api_base_url,
            poll_interval_seconds=poll_interval_seconds,
            alert_consumer_api_token=alert_consumer_api_token,
            discord_alert_cursor_file=discord_alert_cursor_file,
            discord_alert_replay_on_first_start=discord_alert_replay_on_first_start,
            status_schedule_state_file=status_schedule_state_file,
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


def _parse_alert_cursor_file(source: Mapping[str, str]) -> str:
    raw_value = _get_raw(source, "DISCORD_ALERT_CURSOR_FILE")
    if raw_value is None:
        return str(_DEFAULT_ALERT_CURSOR_FILE)

    path = Path(raw_value).expanduser()
    if not path.is_absolute():
        path = _BOT_DIR / path
    return str(path)


def _parse_monitoring_api_base_url(source: Mapping[str, str]) -> str:
    raw_value = _get_raw(source, "MONITORING_API_BASE_URL") or _get_raw(
        source,
        "MONITOR_API_BASE_URL",
    )
    if raw_value is None:
        raise ValueError("MONITORING_API_BASE_URL is required.")
    normalized = raw_value.rstrip("/")
    if normalized.endswith("/api"):
        return normalized
    return f"{normalized}/api"
