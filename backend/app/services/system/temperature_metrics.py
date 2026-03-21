from __future__ import annotations

import logging
import os
from collections.abc import Iterable

from app.services.system.common import read_text_file

try:
    import psutil
except ImportError:  # pragma: no cover - handled at runtime
    psutil = None  # type: ignore[assignment]

logger = logging.getLogger(__name__)

CPU_KEYWORDS = (
    "cpu",
    "core",
    "package",
    "coretemp",
    "k10temp",
    "zenpower",
    "x86_pkg",
    "tctl",
    "tdie",
)
CPU_EXCLUDE_KEYWORDS = (
    "gpu",
    "nvme",
    "drivetemp",
    "hdd",
    "ssd",
    "pch",
    "acpitz",
    "chassis",
    "ambient",
)
CHASSIS_KEYWORDS = (
    "acpitz",
    "pch",
    "systin",
    "system",
    "chassis",
    "ambient",
    "board",
    "motherboard",
    "mb",
)
CHASSIS_EXCLUDE_KEYWORDS = (
    "cpu",
    "core",
    "package",
    "x86_pkg",
    "tdie",
    "tctl",
    "gpu",
    "nvme",
    "drivetemp",
)
SYSFS_CPU_TYPE_KEYWORDS = (
    "cpu",
    "x86_pkg",
    "package",
    "k10temp",
    "coretemp",
)
SYSFS_CHASSIS_TYPE_KEYWORDS = (
    "acpitz",
    "pch",
    "ambient",
    "chassis",
    "system",
    "board",
)


def get_cpu_temperature_c() -> float | None:
    candidates = _temperatures_from_psutil(
        include_keywords=CPU_KEYWORDS,
        exclude_keywords=CPU_EXCLUDE_KEYWORDS,
    )
    if candidates:
        return round(max(candidates), 1)

    sysfs_candidates = _temperatures_from_sysfs(type_keywords=SYSFS_CPU_TYPE_KEYWORDS)
    if sysfs_candidates:
        return round(max(sysfs_candidates), 1)
    return None


def get_chassis_temperature_c() -> float | None:
    sysfs_candidates = _temperatures_from_sysfs(type_keywords=SYSFS_CHASSIS_TYPE_KEYWORDS)
    if sysfs_candidates:
        return round(max(sysfs_candidates), 1)

    candidates = _temperatures_from_psutil(
        include_keywords=CHASSIS_KEYWORDS,
        exclude_keywords=CHASSIS_EXCLUDE_KEYWORDS,
    )
    if candidates:
        return round(max(candidates), 1)
    return None


def _temperatures_from_psutil(*, include_keywords: tuple[str, ...], exclude_keywords: tuple[str, ...]) -> list[float]:
    if psutil is None or not hasattr(psutil, "sensors_temperatures"):
        return []

    try:
        sensors = psutil.sensors_temperatures(fahrenheit=False)
    except (AttributeError, OSError, NotImplementedError) as exc:
        logger.debug("Could not read psutil temperature sensors: %s", exc)
        return []

    candidates: list[float] = []
    for sensor_group, entries in (sensors or {}).items():
        for entry in entries or []:
            label = str(getattr(entry, "label", "") or "")
            search_blob = f"{sensor_group} {label}".lower()
            if not _contains_any(search_blob, include_keywords):
                continue
            if _contains_any(search_blob, exclude_keywords):
                continue

            temperature_c = _normalize_temperature_c(getattr(entry, "current", None))
            if temperature_c is not None:
                candidates.append(temperature_c)
    return candidates


def _temperatures_from_sysfs(*, type_keywords: tuple[str, ...]) -> list[float]:
    if os.name == "nt":
        return []

    thermal_root = "/sys/class/thermal"
    if not os.path.isdir(thermal_root):
        return []

    candidates: list[float] = []
    for zone_name in _iter_thermal_zones(thermal_root):
        zone_dir = os.path.join(thermal_root, zone_name)
        zone_type = (read_text_file(os.path.join(zone_dir, "type")) or "").lower()
        if not zone_type:
            continue
        if not _contains_any(zone_type, type_keywords):
            continue

        raw_temp = read_text_file(os.path.join(zone_dir, "temp"))
        parsed = _parse_sysfs_temperature(raw_temp)
        if parsed is not None:
            candidates.append(parsed)
    return candidates


def _iter_thermal_zones(thermal_root: str) -> Iterable[str]:
    try:
        entries = os.listdir(thermal_root)
    except OSError as exc:
        logger.debug("Could not list thermal zones: %s", exc)
        return []
    return [entry for entry in entries if entry.startswith("thermal_zone")]


def _parse_sysfs_temperature(raw_value: str | None) -> float | None:
    if raw_value is None:
        return None
    try:
        value = float(raw_value.strip())
    except ValueError:
        return None

    if abs(value) >= 1000:
        value = value / 1000.0
    return _normalize_temperature_c(value)


def _normalize_temperature_c(raw_value: object) -> float | None:
    if raw_value is None:
        return None
    try:
        value = float(raw_value)
    except (TypeError, ValueError):
        return None

    # Filter clearly invalid values while keeping realistic CPU/chassis ranges.
    if value < -20 or value > 130:
        return None
    return round(value, 1)


def _contains_any(text: str, keywords: tuple[str, ...]) -> bool:
    return any(keyword in text for keyword in keywords)
