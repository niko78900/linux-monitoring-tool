from __future__ import annotations

import json
import logging
from dataclasses import dataclass
from pathlib import Path

from bot_constants import STATUS_SCHEDULE_MODE_FIXED, STATUS_SCHEDULE_MODE_WINDOWS
from schedule_policy import ScheduleMode, TimeWindowRule, parse_windows_payload, serialize_windows_payload

logger = logging.getLogger("linux_monitoring.bot")


@dataclass(frozen=True)
class StatusScheduleState:
    mode: ScheduleMode
    guild_id: int
    channel_id: int
    interval_seconds: int
    windows: list[TimeWindowRule]


def load_status_schedule_state(
    *,
    path: Path,
    configured_guild_id: int | None,
    min_interval_seconds: int,
    max_interval_seconds: int,
) -> StatusScheduleState | None:
    if not path.exists():
        return None

    try:
        raw_text = path.read_text(encoding="utf-8")
        payload = json.loads(raw_text)
    except (OSError, json.JSONDecodeError) as exc:
        logger.warning("Could not read status schedule state from %s: %s", path, exc)
        return None

    if not isinstance(payload, dict):
        logger.warning("Status schedule state file is not an object: %s", path)
        return None

    channel_id_value = payload.get("channel_id")
    guild_id_value = payload.get("guild_id")
    mode_value = str(payload.get("mode") or STATUS_SCHEDULE_MODE_FIXED).strip().lower()
    mode: ScheduleMode
    if mode_value == STATUS_SCHEDULE_MODE_WINDOWS:
        mode = STATUS_SCHEDULE_MODE_WINDOWS
    elif mode_value == STATUS_SCHEDULE_MODE_FIXED:
        mode = STATUS_SCHEDULE_MODE_FIXED
    else:
        logger.warning("Unknown status schedule mode in state file: %s", mode_value)
        return None

    channel_id = _safe_positive_int(channel_id_value)
    guild_id = _safe_positive_int(guild_id_value)
    if guild_id is None:
        guild_id = configured_guild_id

    guild_valid = guild_id is not None
    if configured_guild_id is not None:
        guild_valid = guild_id == configured_guild_id

    if channel_id is None or not guild_valid:
        logger.warning("Status schedule state has invalid values and will be ignored.")
        return None

    interval_seconds = 3600
    windows: list[TimeWindowRule] = []

    if mode == STATUS_SCHEDULE_MODE_FIXED:
        interval_seconds_value = payload.get("interval_seconds")
        parsed_interval_seconds = _safe_positive_int(interval_seconds_value)
        interval_valid = parsed_interval_seconds is not None and min_interval_seconds <= parsed_interval_seconds <= max_interval_seconds
        if not interval_valid:
            logger.warning("Invalid fixed schedule interval in state file.")
            return None
        interval_seconds = parsed_interval_seconds
    else:
        raw_windows = payload.get("windows")
        try:
            parsed_windows = parse_windows_payload(
                raw_windows,
                min_interval_seconds=min_interval_seconds,
                max_interval_seconds=max_interval_seconds,
            )
        except ValueError as exc:
            logger.warning("Invalid windows schedule in state file: %s", exc)
            return None
        if not parsed_windows:
            logger.warning("Windows schedule state is empty.")
            return None
        windows = parsed_windows

    return StatusScheduleState(
        mode=mode,
        guild_id=guild_id,
        channel_id=channel_id,
        interval_seconds=interval_seconds,
        windows=windows,
    )


def save_status_schedule_state(
    *,
    path: Path,
    mode: ScheduleMode,
    guild_id: int | None,
    channel_id: int | None,
    interval_seconds: int,
    windows: list[TimeWindowRule],
) -> None:
    if channel_id is None or guild_id is None:
        return

    payload = {
        "mode": mode,
        "guild_id": guild_id,
        "channel_id": channel_id,
        "interval_seconds": interval_seconds,
        "windows": serialize_windows_payload(windows),
    }
    serialized = json.dumps(payload, separators=(",", ":"), sort_keys=True)

    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp_path = path.with_name(path.name + ".tmp")
        tmp_path.write_text(serialized, encoding="utf-8")
        tmp_path.replace(path)
    except OSError as exc:
        logger.warning("Could not persist status schedule state to %s: %s", path, exc)


def clear_status_schedule_state(path: Path) -> None:
    try:
        if path.exists():
            path.unlink()
    except OSError as exc:
        logger.warning("Could not clear status schedule state at %s: %s", path, exc)


def _safe_positive_int(value: object) -> int | None:
    try:
        parsed = int(value)  # type: ignore[arg-type]
    except (TypeError, ValueError):
        return None
    if parsed <= 0:
        return None
    return parsed
