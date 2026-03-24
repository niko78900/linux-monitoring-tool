from __future__ import annotations

import re
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone, tzinfo
from typing import Any, Literal

ScheduleMode = Literal["fixed", "windows"]
_MINUTES_PER_DAY = 24 * 60
_WINDOW_SPEC_RE = re.compile(r"^\s*(\d{1,2}:\d{2})\s*-\s*(\d{1,2}:\d{2})\s*=\s*(\d+)\s*$")


@dataclass(frozen=True)
class TimeWindowRule:
    start_minute: int
    end_minute: int
    interval_seconds: int


@dataclass(frozen=True)
class NextScheduleEvent:
    run_at_utc: datetime
    should_send: bool


def parse_windows_spec(
    raw_spec: str,
    *,
    min_interval_minutes: int,
    max_interval_minutes: int,
    max_rules: int,
) -> list[TimeWindowRule]:
    parts = [part.strip() for part in re.split(r"[;,]", raw_spec or "") if part.strip()]
    if not parts:
        raise ValueError("No windows provided. Use format like `12:00-15:00=15;15:00-18:00=60`.")
    if len(parts) > max_rules:
        raise ValueError(f"Too many windows. Maximum allowed is {max_rules}.")

    windows: list[TimeWindowRule] = []
    for part in parts:
        match = _WINDOW_SPEC_RE.match(part)
        if match is None:
            raise ValueError(f"Invalid segment `{part}`. Expected `HH:MM-HH:MM=MINUTES`.")

        start_text, end_text, interval_text = match.groups()
        start_minute = _parse_time_to_minute(start_text)
        end_minute = _parse_time_to_minute(end_text)
        if start_minute == end_minute:
            raise ValueError(f"Window `{part}` has identical start and end time.")

        interval_minutes = int(interval_text)
        if interval_minutes < min_interval_minutes or interval_minutes > max_interval_minutes:
            raise ValueError(
                f"Window `{part}` interval must be between {min_interval_minutes} and {max_interval_minutes} minutes."
            )

        windows.append(
            TimeWindowRule(
                start_minute=start_minute,
                end_minute=end_minute,
                interval_seconds=interval_minutes * 60,
            )
        )

    _validate_no_overlaps(windows)
    return windows


def parse_windows_payload(
    raw_windows: object,
    *,
    min_interval_seconds: int,
    max_interval_seconds: int,
) -> list[TimeWindowRule]:
    if not isinstance(raw_windows, list):
        raise ValueError("`windows` must be a list.")

    windows: list[TimeWindowRule] = []
    for item in raw_windows:
        if not isinstance(item, dict):
            raise ValueError("Each schedule window must be an object.")

        start_minute = _safe_int(item.get("start_minute"))
        end_minute = _safe_int(item.get("end_minute"))
        interval_seconds = _safe_int(item.get("interval_seconds"))
        if start_minute is None or end_minute is None or interval_seconds is None:
            raise ValueError("Schedule window values must be integers.")
        if start_minute < 0 or start_minute >= _MINUTES_PER_DAY:
            raise ValueError("`start_minute` must be between 0 and 1439.")
        if end_minute < 0 or end_minute >= _MINUTES_PER_DAY:
            raise ValueError("`end_minute` must be between 0 and 1439.")
        if start_minute == end_minute:
            raise ValueError("Schedule windows cannot have identical start/end.")
        if interval_seconds < min_interval_seconds or interval_seconds > max_interval_seconds:
            raise ValueError("Schedule window interval is outside allowed bounds.")

        windows.append(
            TimeWindowRule(
                start_minute=start_minute,
                end_minute=end_minute,
                interval_seconds=interval_seconds,
            )
        )

    _validate_no_overlaps(windows)
    return windows


def serialize_windows_payload(windows: list[TimeWindowRule]) -> list[dict[str, int]]:
    payload: list[dict[str, int]] = []
    for window in windows:
        payload.append(
            {
                "start_minute": window.start_minute,
                "end_minute": window.end_minute,
                "interval_seconds": window.interval_seconds,
            }
        )
    return payload


def format_windows_for_display(windows: list[TimeWindowRule]) -> list[str]:
    lines: list[str] = []
    for window in sorted(windows, key=lambda value: value.start_minute):
        lines.append(
            f"{_format_minute(window.start_minute)}-{_format_minute(window.end_minute)}"
            f": every {window.interval_seconds // 60} minute(s)"
        )
    return lines


def compute_next_event(
    *,
    mode: ScheduleMode,
    now_utc: datetime,
    fixed_interval_seconds: int,
    windows: list[TimeWindowRule],
    local_tz: tzinfo | None = None,
) -> NextScheduleEvent | None:
    now_utc = _to_utc(now_utc)
    if mode != "windows":
        return NextScheduleEvent(
            run_at_utc=now_utc + timedelta(seconds=fixed_interval_seconds),
            should_send=True,
        )
    if not windows:
        return None

    now_local = _to_local(now_utc=now_utc, local_tz=local_tz)
    active_window = _find_active_window(windows, now_local)
    if active_window is None:
        next_start = _next_window_start(now_local=now_local, windows=windows)
        return NextScheduleEvent(run_at_utc=next_start.astimezone(timezone.utc), should_send=False)

    interval_target = now_local + timedelta(seconds=active_window.interval_seconds)
    boundary_target = _next_time_for_minute(now_local=now_local, minute_of_day=active_window.end_minute)
    if boundary_target < interval_target:
        return NextScheduleEvent(run_at_utc=boundary_target.astimezone(timezone.utc), should_send=False)

    return NextScheduleEvent(run_at_utc=interval_target.astimezone(timezone.utc), should_send=True)


def _validate_no_overlaps(windows: list[TimeWindowRule]) -> None:
    owners = [-1] * _MINUTES_PER_DAY
    for index, window in enumerate(windows):
        for minute in _iter_minutes(window.start_minute, window.end_minute):
            owner = owners[minute]
            if owner != -1:
                raise ValueError("Schedule windows overlap. Adjust ranges so each time belongs to at most one window.")
            owners[minute] = index


def _iter_minutes(start_minute: int, end_minute: int) -> list[int]:
    minutes: list[int] = []
    minute = start_minute
    while minute != end_minute:
        minutes.append(minute)
        minute = (minute + 1) % _MINUTES_PER_DAY
    return minutes


def _find_active_window(windows: list[TimeWindowRule], now_local: datetime) -> TimeWindowRule | None:
    minute_of_day = now_local.hour * 60 + now_local.minute
    for window in windows:
        if _contains_minute(window, minute_of_day):
            return window
    return None


def _contains_minute(window: TimeWindowRule, minute_of_day: int) -> bool:
    if window.start_minute < window.end_minute:
        return window.start_minute <= minute_of_day < window.end_minute
    return minute_of_day >= window.start_minute or minute_of_day < window.end_minute


def _next_window_start(*, now_local: datetime, windows: list[TimeWindowRule]) -> datetime:
    candidates = [_next_time_for_minute(now_local=now_local, minute_of_day=window.start_minute) for window in windows]
    return min(candidates)


def _next_time_for_minute(*, now_local: datetime, minute_of_day: int) -> datetime:
    candidate = now_local.replace(
        hour=minute_of_day // 60,
        minute=minute_of_day % 60,
        second=0,
        microsecond=0,
    )
    if candidate <= now_local:
        candidate = candidate + timedelta(days=1)
    return candidate


def _parse_time_to_minute(raw_value: str) -> int:
    parts = raw_value.split(":")
    hour = int(parts[0])
    minute = int(parts[1])
    if hour < 0 or hour > 23 or minute < 0 or minute > 59:
        raise ValueError(f"Invalid time `{raw_value}`. Use 24h HH:MM format.")
    return hour * 60 + minute


def _format_minute(value: int) -> str:
    return f"{value // 60:02d}:{value % 60:02d}"


def _safe_int(value: Any) -> int | None:
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def _to_utc(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


def _to_local(*, now_utc: datetime, local_tz: tzinfo | None) -> datetime:
    timezone_value = local_tz
    if timezone_value is None:
        timezone_value = datetime.now().astimezone().tzinfo
    if timezone_value is None:
        timezone_value = timezone.utc
    return now_utc.astimezone(timezone_value)
