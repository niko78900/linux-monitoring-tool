from __future__ import annotations

from datetime import datetime, timezone


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def to_utc_datetime(epoch_seconds: float) -> datetime:
    return datetime.fromtimestamp(epoch_seconds, tz=timezone.utc)


def format_duration(total_seconds: int) -> str:
    safe_seconds = max(0, int(total_seconds))
    days, rem = divmod(safe_seconds, 86400)
    hours, rem = divmod(rem, 3600)
    minutes, seconds = divmod(rem, 60)

    parts: list[str] = []
    if days:
        parts.append(f"{days}d")
    parts.append(f"{hours:02d}h")
    parts.append(f"{minutes:02d}m")
    parts.append(f"{seconds:02d}s")
    return " ".join(parts)


def parse_docker_timestamp(raw_value: str | None) -> datetime | None:
    if not raw_value:
        return None

    value = raw_value.strip()
    if value.endswith("Z"):
        value = f"{value[:-1]}+00:00"

    if "." in value:
        head, tail = value.split(".", 1)
        plus_pos = tail.find("+")
        minus_pos = tail.find("-")
        tz_pos_candidates = [pos for pos in (plus_pos, minus_pos) if pos != -1]
        tz_pos = min(tz_pos_candidates) if tz_pos_candidates else -1

        fraction = tail if tz_pos == -1 else tail[:tz_pos]
        timezone_part = "" if tz_pos == -1 else tail[tz_pos:]
        normalized_fraction = (fraction + "000000")[:6]
        value = f"{head}.{normalized_fraction}{timezone_part}"

    try:
        parsed = datetime.fromisoformat(value)
    except ValueError:
        return None

    if parsed.tzinfo is None:
        return parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)
