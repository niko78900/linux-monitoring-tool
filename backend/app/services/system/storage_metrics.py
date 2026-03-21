from __future__ import annotations

import json
import logging
import os
import re
import shutil
import subprocess
import time
from threading import Lock

from app.models.system import (
    DiskDeviceMetrics,
    DiskHealth,
    DiskMetrics,
    PhysicalDiskMetrics,
    RaidArrayMetrics,
    RaidHealth,
)
from app.services.system.base_metrics import fallback_mountpoint
from app.services.system.common import (
    is_physical_block_device_name,
    is_relevant_partition,
    normalize_block_device_name,
    parse_bool_text,
    parse_int,
    read_text_file,
)

try:
    import psutil
except ImportError:  # pragma: no cover - handled at runtime
    psutil = None  # type: ignore[assignment]

logger = logging.getLogger(__name__)
_DISK_TEMPERATURE_CACHE_TTL_SECONDS = 30.0
_disk_temperature_cache: dict[str, tuple[float, float | None]] = {}
_disk_temperature_cache_lock = Lock()


def get_disks_metrics(mountpoint: str, primary_disk: DiskMetrics, raid_arrays: list[RaidArrayMetrics]) -> list[DiskDeviceMetrics]:
    primary_mountpoint = primary_disk.mountpoint or mountpoint or fallback_mountpoint()

    if psutil is None:
        return [
            _to_disk_device_metrics(
                device="unknown",
                mountpoint=primary_mountpoint,
                fstype="unknown",
                total=primary_disk.total,
                used=primary_disk.used,
                free=primary_disk.free,
                percent=primary_disk.percent,
                read_only=False,
                available=False,
                reason="psutil is unavailable.",
            )
        ]

    disks = _collect_partition_disk_metrics(raid_arrays)
    has_primary = any(disk.mountpoint == primary_mountpoint for disk in disks)
    if not has_primary:
        primary_available = primary_disk.total > 0
        disks.append(
            _to_disk_device_metrics(
                device="unknown",
                mountpoint=primary_mountpoint,
                fstype="unknown",
                total=primary_disk.total,
                used=primary_disk.used,
                free=primary_disk.free,
                percent=primary_disk.percent,
                read_only=False,
                available=primary_available,
                reason=None if primary_available else "Disk metrics unavailable.",
            )
        )

    disks.sort(key=lambda disk: (0 if disk.mountpoint == primary_mountpoint else 1, disk.mountpoint.lower()))
    return disks


def get_raid_arrays_metrics() -> list[RaidArrayMetrics]:
    if os.name == "nt":
        return []

    sys_block = "/sys/block"
    if not os.path.isdir(sys_block):
        return []

    arrays: list[RaidArrayMetrics] = []
    try:
        block_devices = os.listdir(sys_block)
    except OSError as exc:
        logger.warning("Could not list block devices for RAID discovery: %s", exc)
        return []

    for block_device in block_devices:
        if not block_device.startswith("md"):
            continue

        md_dir = os.path.join(sys_block, block_device, "md")
        if not os.path.isdir(md_dir):
            continue

        device = f"/dev/{block_device}"
        level = read_text_file(os.path.join(md_dir, "level")) or "unknown"
        state = read_text_file(os.path.join(md_dir, "array_state")) or "unknown"
        raid_disks = parse_int(read_text_file(os.path.join(md_dir, "raid_disks")))
        degraded_devices = parse_int(read_text_file(os.path.join(md_dir, "degraded")))
        sync_action = read_text_file(os.path.join(md_dir, "sync_action"))

        slaves_dir = os.path.join(sys_block, block_device, "slaves")
        members: list[str] = []
        if os.path.isdir(slaves_dir):
            try:
                members = sorted(f"/dev/{name}" for name in os.listdir(slaves_dir))
            except OSError as exc:
                logger.warning("Could not read RAID member devices for %s: %s", device, exc)

        active_devices = max(0, raid_disks - degraded_devices) if raid_disks > 0 else len(members)
        arrays.append(
            RaidArrayMetrics(
                name=block_device,
                device=device,
                level=level,
                state=state,
                raid_disks=raid_disks,
                active_devices=active_devices,
                degraded_devices=degraded_devices,
                sync_action=sync_action,
                members=members,
                health=_build_raid_health(
                    level=level,
                    state=state,
                    degraded_devices=degraded_devices,
                    sync_action=sync_action,
                ),
            )
        )

    arrays.sort(key=lambda raid_array: raid_array.device.lower())
    return arrays


def get_physical_disks_metrics(raid_arrays: list[RaidArrayMetrics]) -> list[PhysicalDiskMetrics]:
    if os.name == "nt":
        return []

    sys_block = "/sys/block"
    if not os.path.isdir(sys_block):
        return []

    try:
        block_devices = os.listdir(sys_block)
    except OSError as exc:
        logger.warning("Could not list physical block devices: %s", exc)
        return []

    mounts_by_disk = _collect_mountpoints_by_physical_disk()
    raid_membership = _build_raid_membership_by_physical_disk(raid_arrays)

    physical_disks: list[PhysicalDiskMetrics] = []
    for device_name in block_devices:
        if not is_physical_block_device_name(device_name):
            continue

        device_path = os.path.join(sys_block, device_name)
        if not os.path.isdir(device_path):
            continue

        # Skip pseudo devices that do not represent a real hardware-backed disk.
        if not os.path.exists(os.path.join(device_path, "device")):
            continue

        size_sectors = parse_int(read_text_file(os.path.join(device_path, "size")))
        logical_block_size = parse_int(read_text_file(os.path.join(device_path, "queue", "logical_block_size")), default=512)
        size_bytes = size_sectors * logical_block_size

        state = read_text_file(os.path.join(device_path, "device", "state"))
        model = read_text_file(os.path.join(device_path, "device", "model"))
        vendor = read_text_file(os.path.join(device_path, "device", "vendor"))
        serial = read_text_file(os.path.join(device_path, "device", "serial"))
        rotational_value = read_text_file(os.path.join(device_path, "queue", "rotational"))
        rotational = None
        if rotational_value is not None:
            rotational = rotational_value.strip() == "1"
        removable = parse_bool_text(read_text_file(os.path.join(device_path, "removable")))
        mounted_partitions = mounts_by_disk.get(device_name, [])
        disk_raid_arrays = raid_membership.get(device_name, [])
        raid_array_names = [raid_array.name for raid_array in disk_raid_arrays]
        temperature_c = _get_disk_temperature_c_cached(device_name)

        physical_disks.append(
            PhysicalDiskMetrics(
                name=device_name,
                device=f"/dev/{device_name}",
                model=model,
                vendor=vendor,
                serial=serial,
                size_bytes=size_bytes,
                temperature_c=temperature_c,
                rotational=rotational,
                removable=removable,
                state=state,
                mounted_partitions=mounted_partitions,
                raid_arrays=raid_array_names,
                health=_build_physical_disk_health(
                    size_bytes=size_bytes,
                    state=state,
                    raid_arrays=disk_raid_arrays,
                ),
            )
        )

    physical_disks.sort(key=lambda disk: disk.device.lower())
    return physical_disks


def _mount_options_set(options: str) -> set[str]:
    return {item.strip().lower() for item in options.split(",") if item.strip()}


def _build_disk_health(percent: float, available: bool, read_only: bool, reason: str | None = None) -> DiskHealth:
    if not available:
        return DiskHealth(status="unknown", reason=reason or "Disk metrics unavailable.")
    if percent >= 95:
        return DiskHealth(status="critical", reason="Disk usage is above 95%.")
    if percent >= 85:
        return DiskHealth(status="warning", reason="Disk usage is above 85%.")
    if read_only:
        return DiskHealth(status="warning", reason="Disk is mounted read-only.")
    return DiskHealth(status="healthy", reason="Disk usage is within normal range.")


def _to_disk_device_metrics(
    *,
    device: str,
    mountpoint: str,
    fstype: str,
    total: int,
    used: int,
    free: int,
    percent: float,
    read_only: bool,
    available: bool,
    raid_array: str | None = None,
    raid_level: str | None = None,
    reason: str | None = None,
) -> DiskDeviceMetrics:
    return DiskDeviceMetrics(
        device=device or "unknown",
        mountpoint=mountpoint,
        fstype=fstype or "unknown",
        total=total,
        used=used,
        free=free,
        percent=percent,
        read_only=read_only,
        available=available,
        raid_array=raid_array,
        raid_level=raid_level,
        health=_build_disk_health(percent=percent, available=available, read_only=read_only, reason=reason),
    )


def _find_raid_array_for_device(device: str, raid_arrays_by_device: dict[str, RaidArrayMetrics]) -> RaidArrayMetrics | None:
    if not device:
        return None

    candidates = [device]
    md_partition_match = re.match(r"^(\/dev\/md[^\/\s]+)p\d+$", device)
    if md_partition_match:
        candidates.append(md_partition_match.group(1))

    md_named_partition_match = re.match(r"^(\/dev\/md\/[^\/\s]+)p\d+$", device)
    if md_named_partition_match:
        candidates.append(md_named_partition_match.group(1))

    for candidate in candidates:
        raid_array = raid_arrays_by_device.get(candidate)
        if raid_array is not None:
            return raid_array
    return None


def _build_raid_array_device_map(raid_arrays: list[RaidArrayMetrics]) -> dict[str, RaidArrayMetrics]:
    raid_arrays_by_device = {raid_array.device: raid_array for raid_array in raid_arrays}
    md_dir = "/dev/md"
    if not os.path.isdir(md_dir):
        return raid_arrays_by_device

    try:
        aliases = os.listdir(md_dir)
    except OSError as exc:
        logger.warning("Could not list RAID aliases in %s: %s", md_dir, exc)
        return raid_arrays_by_device

    for alias in aliases:
        alias_path = os.path.join(md_dir, alias)
        resolved_path = os.path.realpath(alias_path)
        raid_array = raid_arrays_by_device.get(resolved_path)
        if raid_array is not None:
            raid_arrays_by_device[alias_path] = raid_array

    return raid_arrays_by_device


def _collect_partition_disk_metrics(raid_arrays: list[RaidArrayMetrics]) -> list[DiskDeviceMetrics]:
    if psutil is None:
        return []

    try:
        partitions = psutil.disk_partitions(all=False)
    except (AttributeError, OSError) as exc:
        logger.warning("Could not list disk partitions: %s", exc)
        return []

    raid_arrays_by_device = _build_raid_array_device_map(raid_arrays)
    disks_by_mountpoint: dict[str, DiskDeviceMetrics] = {}
    for partition in partitions:
        mountpoint = str(getattr(partition, "mountpoint", "") or "")
        fstype = str(getattr(partition, "fstype", "") or "unknown")
        if not is_relevant_partition(mountpoint, fstype):
            continue

        device = str(getattr(partition, "device", "") or "unknown")
        options = str(getattr(partition, "opts", "") or "")
        read_only = "ro" in _mount_options_set(options)
        raid_array = _find_raid_array_for_device(device, raid_arrays_by_device)
        raid_array_name = raid_array.name if raid_array is not None else None
        raid_array_level = raid_array.level if raid_array is not None else None

        try:
            usage = psutil.disk_usage(mountpoint)
            disk_metric = _to_disk_device_metrics(
                device=device,
                mountpoint=mountpoint,
                fstype=fstype,
                total=int(usage.total),
                used=int(usage.used),
                free=int(usage.free),
                percent=round(float(usage.percent), 2),
                read_only=read_only,
                available=True,
                raid_array=raid_array_name,
                raid_level=raid_array_level,
            )
        except (AttributeError, OSError, PermissionError) as exc:
            logger.warning("Could not read disk usage for mountpoint %s: %s", mountpoint, exc)
            disk_metric = _to_disk_device_metrics(
                device=device,
                mountpoint=mountpoint,
                fstype=fstype,
                total=0,
                used=0,
                free=0,
                percent=0.0,
                read_only=read_only,
                available=False,
                raid_array=raid_array_name,
                raid_level=raid_array_level,
                reason=f"Metrics unavailable: {exc}",
            )

        existing = disks_by_mountpoint.get(mountpoint)
        if (
            existing is None
            or (not existing.available and disk_metric.available)
            or (existing.raid_array is None and disk_metric.raid_array is not None)
        ):
            disks_by_mountpoint[mountpoint] = disk_metric

    return list(disks_by_mountpoint.values())


def _build_raid_health(level: str, state: str, degraded_devices: int, sync_action: str | None) -> RaidHealth:
    normalized_state = state.strip().lower()
    normalized_sync = (sync_action or "").strip().lower()
    normalized_level = level.strip().lower()

    if degraded_devices > 0:
        return RaidHealth(
            status="critical",
            reason=f"Array is degraded ({degraded_devices} missing device{'s' if degraded_devices > 1 else ''}).",
        )

    if normalized_state in {"inactive", "clear", "suspended"}:
        return RaidHealth(status="warning", reason=f"Array state is '{state}'.")

    if normalized_sync and normalized_sync not in {"idle", "none"}:
        return RaidHealth(status="warning", reason=f"Array sync action is '{sync_action}'.")

    if normalized_level == "unknown":
        return RaidHealth(status="unknown", reason="RAID level could not be determined.")

    return RaidHealth(status="healthy", reason="RAID array reports healthy state.")


def _collect_mountpoints_by_physical_disk() -> dict[str, list[str]]:
    mounts_by_disk: dict[str, set[str]] = {}
    if psutil is None:
        return {}

    try:
        partitions = psutil.disk_partitions(all=False)
    except (AttributeError, OSError) as exc:
        logger.warning("Could not collect partitions for physical disks: %s", exc)
        return {}

    for partition in partitions:
        mountpoint = str(getattr(partition, "mountpoint", "") or "").strip()
        fstype = str(getattr(partition, "fstype", "") or "").strip()
        device = str(getattr(partition, "device", "") or "").strip()
        if not mountpoint or not device:
            continue
        if not is_relevant_partition(mountpoint, fstype):
            continue

        disk_name = normalize_block_device_name(device)
        if not is_physical_block_device_name(disk_name):
            continue

        mounts_by_disk.setdefault(disk_name, set()).add(mountpoint)

    return {
        disk_name: sorted(mounts)
        for disk_name, mounts in mounts_by_disk.items()
    }


def _build_raid_membership_by_physical_disk(raid_arrays: list[RaidArrayMetrics]) -> dict[str, list[RaidArrayMetrics]]:
    membership: dict[str, list[RaidArrayMetrics]] = {}
    for raid_array in raid_arrays:
        for member in raid_array.members:
            disk_name = normalize_block_device_name(member)
            if not is_physical_block_device_name(disk_name):
                continue
            membership.setdefault(disk_name, []).append(raid_array)

    for disk_name, arrays in membership.items():
        unique_arrays = {array.device: array for array in arrays}
        membership[disk_name] = sorted(unique_arrays.values(), key=lambda item: item.device.lower())
    return membership


def _build_physical_disk_health(
    *,
    size_bytes: int,
    state: str | None,
    raid_arrays: list[RaidArrayMetrics],
) -> DiskHealth:
    if size_bytes <= 0:
        return DiskHealth(status="unknown", reason="Disk size could not be determined.")

    normalized_state = (state or "").strip().lower()
    if normalized_state in {"offline", "faulty", "error", "dead"}:
        return DiskHealth(status="critical", reason=f"Kernel reports disk state '{state}'.")
    if normalized_state and normalized_state not in {"running", "live", "active"}:
        return DiskHealth(status="warning", reason=f"Kernel reports disk state '{state}'.")

    if raid_arrays:
        if any(raid_array.health.status == "critical" for raid_array in raid_arrays):
            return DiskHealth(status="warning", reason="Member of a degraded RAID array.")
        if any(raid_array.health.status == "warning" for raid_array in raid_arrays):
            return DiskHealth(status="warning", reason="Member of a RAID array under sync/recovery.")

    return DiskHealth(status="healthy", reason="Physical disk reports healthy kernel state.")


def _get_disk_temperature_c_cached(device_name: str) -> float | None:
    if not device_name or os.name == "nt":
        return None

    now = time.monotonic()
    with _disk_temperature_cache_lock:
        cached = _disk_temperature_cache.get(device_name)
        if cached is not None:
            timestamp, value = cached
            if now - timestamp <= _DISK_TEMPERATURE_CACHE_TTL_SECONDS:
                return value

    value = _read_disk_temperature_c(device_name)
    with _disk_temperature_cache_lock:
        _disk_temperature_cache[device_name] = (now, value)
    return value


def _read_disk_temperature_c(device_name: str) -> float | None:
    device_path = f"/dev/{device_name}"

    smartctl_path = shutil.which("smartctl")
    if smartctl_path is not None:
        json_output = _run_safe_command([smartctl_path, "-A", "-j", device_path], timeout_seconds=2.5)
        if json_output is not None:
            parsed_json_temperature = _parse_smartctl_json_temperature(json_output)
            if parsed_json_temperature is not None:
                return parsed_json_temperature

        text_output = _run_safe_command([smartctl_path, "-A", device_path], timeout_seconds=2.5)
        if text_output is not None:
            parsed_text_temperature = _parse_smartctl_text_temperature(text_output)
            if parsed_text_temperature is not None:
                return parsed_text_temperature

    return _read_disk_temperature_from_psutil(device_name)


def _run_safe_command(args: list[str], timeout_seconds: float) -> str | None:
    try:
        result = subprocess.run(
            args,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            errors="ignore",
            timeout=timeout_seconds,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        logger.debug("Command failed (%s): %s", args[0] if args else "unknown", exc)
        return None

    if result.returncode != 0:
        return None

    output = result.stdout.strip()
    return output or None


def _parse_smartctl_json_temperature(raw_output: str) -> float | None:
    try:
        payload = json.loads(raw_output)
    except json.JSONDecodeError:
        return None
    if not isinstance(payload, dict):
        return None

    candidates: list[float] = []

    temperature_obj = payload.get("temperature")
    temperature_data = temperature_obj if isinstance(temperature_obj, dict) else {}
    direct_temperature = _normalize_temperature(temperature_data.get("current"))
    if direct_temperature is not None:
        candidates.append(direct_temperature)

    nvme_obj = payload.get("nvme_smart_health_information_log")
    nvme_data = nvme_obj if isinstance(nvme_obj, dict) else {}
    nvme_temperature = _normalize_temperature(nvme_data.get("temperature"))
    if nvme_temperature is not None:
        candidates.append(nvme_temperature)

    ata_obj = payload.get("ata_smart_attributes")
    ata_data = ata_obj if isinstance(ata_obj, dict) else {}
    ata_table = ata_data.get("table") or []
    for attribute in ata_table:
        if not isinstance(attribute, dict):
            continue
        attr_id = attribute.get("id")
        if attr_id not in {190, 194}:
            continue

        raw_value = (attribute.get("raw") or {}).get("value")
        parsed_raw_value = _normalize_temperature(raw_value)
        if parsed_raw_value is not None:
            candidates.append(parsed_raw_value)
            continue

        raw_string = (attribute.get("raw") or {}).get("string")
        if raw_string:
            parsed_from_string = _parse_first_temperature_number(str(raw_string))
            if parsed_from_string is not None:
                candidates.append(parsed_from_string)

    if not candidates:
        return None
    return round(max(candidates), 1)


def _parse_smartctl_text_temperature(raw_output: str) -> float | None:
    candidates: list[float] = []

    for line in raw_output.splitlines():
        normalized_line = line.strip()
        if not normalized_line:
            continue

        direct_pattern = re.search(
            r"^(?:Temperature|Composite Temperature|Current Drive Temperature)\s*:\s*([+-]?\d+)\b",
            normalized_line,
            flags=re.IGNORECASE,
        )
        if direct_pattern is not None:
            parsed = _normalize_temperature(direct_pattern.group(1))
            if parsed is not None:
                candidates.append(parsed)
            continue

        sensor_pattern = re.search(r"^Temperature Sensor \d+\s*:\s*([+-]?\d+)\b", normalized_line, flags=re.IGNORECASE)
        if sensor_pattern is not None:
            parsed = _normalize_temperature(sensor_pattern.group(1))
            if parsed is not None:
                candidates.append(parsed)
            continue

        smart_table_pattern = re.search(
            r"^(190|194)\s+\S+.*?\s([+-]?\d+)(?:\s*\(.*\))?\s*$",
            normalized_line,
            flags=re.IGNORECASE,
        )
        if smart_table_pattern is not None:
            parsed = _normalize_temperature(smart_table_pattern.group(2))
            if parsed is not None:
                candidates.append(parsed)

    if not candidates:
        return None
    return round(max(candidates), 1)


def _read_disk_temperature_from_psutil(device_name: str) -> float | None:
    if psutil is None or not hasattr(psutil, "sensors_temperatures"):
        return None

    try:
        sensors = psutil.sensors_temperatures(fahrenheit=False)
    except (AttributeError, OSError, NotImplementedError) as exc:
        logger.debug("Could not read psutil temperatures for disk %s: %s", device_name, exc)
        return None

    candidates: list[float] = []
    normalized_device_name = device_name.lower()

    for sensor_group, entries in (sensors or {}).items():
        sensor_group_lower = str(sensor_group).lower()
        for entry in entries or []:
            label = str(getattr(entry, "label", "") or "").lower()
            search_blob = f"{sensor_group_lower} {label}"

            is_disk_group = any(keyword in sensor_group_lower for keyword in ("nvme", "drivetemp", "hdd", "ssd"))
            references_device = normalized_device_name in search_blob
            if not is_disk_group and not references_device:
                continue

            # NVMe sensors often expose only a composite value without explicit device label.
            if not references_device and not normalized_device_name.startswith("nvme"):
                continue

            parsed = _normalize_temperature(getattr(entry, "current", None))
            if parsed is not None:
                candidates.append(parsed)

    if not candidates:
        return None
    return round(max(candidates), 1)


def _parse_first_temperature_number(raw_value: str) -> float | None:
    match = re.search(r"([+-]?\d+)", raw_value)
    if match is None:
        return None
    return _normalize_temperature(match.group(1))


def _normalize_temperature(raw_value: object) -> float | None:
    if raw_value is None:
        return None
    try:
        value = float(raw_value)
    except (TypeError, ValueError):
        return None

    # Some tools may expose Kelvin. Convert if it looks like Kelvin range.
    if 200 <= value <= 500:
        value = value - 273.15

    if value < -20 or value > 130:
        return None
    return value
