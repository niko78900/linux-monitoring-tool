from __future__ import annotations

import logging
import os
import re

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

        physical_disks.append(
            PhysicalDiskMetrics(
                name=device_name,
                device=f"/dev/{device_name}",
                model=model,
                vendor=vendor,
                serial=serial,
                size_bytes=size_bytes,
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
