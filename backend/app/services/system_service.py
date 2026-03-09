from __future__ import annotations

import logging
import os
import platform
import socket
from datetime import datetime

from app.core.utils import format_duration, to_utc_datetime, utc_now
from app.models.system import (
    CpuMetrics,
    DiskDeviceMetrics,
    DiskHealth,
    DiskMetrics,
    LoadAverage,
    MemoryMetrics,
    NetworkMetrics,
    PlatformInfo,
    SwapMetrics,
    SystemResponse,
)

try:
    import psutil
except ImportError:  # pragma: no cover - handled at runtime
    psutil = None  # type: ignore[assignment]

logger = logging.getLogger(__name__)

IGNORED_FSTYPES = {
    "autofs",
    "binfmt_misc",
    "cgroup",
    "cgroup2",
    "configfs",
    "debugfs",
    "devpts",
    "devtmpfs",
    "fusectl",
    "hugetlbfs",
    "mqueue",
    "nsfs",
    "overlay",
    "proc",
    "pstore",
    "ramfs",
    "securityfs",
    "squashfs",
    "sysfs",
    "tmpfs",
    "tracefs",
}

IGNORED_MOUNT_PREFIXES = ("/proc", "/sys", "/dev", "/run", "/snap")


def get_system_metrics(mountpoint: str) -> SystemResponse:
    now = utc_now()
    boot_time = _get_boot_time(now)
    uptime_seconds = max(0, int((now - boot_time).total_seconds()))
    primary_disk = _get_disk_metrics(mountpoint)

    return SystemResponse(
        hostname=_get_hostname(),
        os=_get_platform_info(),
        kernel_version=platform.release(),
        uptime_seconds=uptime_seconds,
        uptime_human=format_duration(uptime_seconds),
        boot_time=boot_time,
        cpu=_get_cpu_metrics(),
        memory=_get_memory_metrics(),
        swap=_get_swap_metrics(),
        disk=primary_disk,
        disks=_get_disks_metrics(mountpoint, primary_disk),
        network=_get_network_metrics(),
    )


def _get_hostname() -> str:
    try:
        return socket.gethostname()
    except OSError as exc:
        logger.warning("Could not read hostname: %s", exc)
        return "unknown"


def _get_platform_info() -> PlatformInfo:
    return PlatformInfo(
        system=platform.system(),
        release=platform.release(),
        version=platform.version(),
        machine=platform.machine(),
        platform=platform.platform(),
    )


def _get_boot_time(now: datetime) -> datetime:
    if psutil is None:
        return now
    try:
        return to_utc_datetime(psutil.boot_time())
    except (AttributeError, OSError) as exc:
        logger.warning("Could not read boot time: %s", exc)
        return now


def _get_load_average() -> LoadAverage | None:
    try:
        one, five, fifteen = os.getloadavg()
    except (AttributeError, OSError):
        return None
    return LoadAverage(
        one_min=round(float(one), 2),
        five_min=round(float(five), 2),
        fifteen_min=round(float(fifteen), 2),
    )


def _get_cpu_metrics() -> CpuMetrics:
    if psutil is None:
        return CpuMetrics(usage_percent=0.0, physical_cores=0, logical_cores=0, load_average=None)

    try:
        usage_percent = round(float(psutil.cpu_percent(interval=0.1)), 2)
    except (AttributeError, OSError) as exc:
        logger.warning("Could not read CPU usage: %s", exc)
        usage_percent = 0.0

    try:
        physical_cores = int(psutil.cpu_count(logical=False) or 0)
        logical_cores = int(psutil.cpu_count(logical=True) or 0)
    except (AttributeError, OSError) as exc:
        logger.warning("Could not read CPU core counts: %s", exc)
        physical_cores = 0
        logical_cores = 0

    return CpuMetrics(
        usage_percent=usage_percent,
        physical_cores=physical_cores,
        logical_cores=logical_cores,
        load_average=_get_load_average(),
    )


def _get_memory_metrics() -> MemoryMetrics:
    if psutil is None:
        return MemoryMetrics(total=0, available=0, used=0, percent=0.0)
    try:
        memory = psutil.virtual_memory()
        return MemoryMetrics(
            total=int(memory.total),
            available=int(memory.available),
            used=int(memory.used),
            percent=round(float(memory.percent), 2),
        )
    except (AttributeError, OSError) as exc:
        logger.warning("Could not read memory metrics: %s", exc)
        return MemoryMetrics(total=0, available=0, used=0, percent=0.0)


def _get_swap_metrics() -> SwapMetrics:
    if psutil is None:
        return SwapMetrics(total=0, used=0, percent=0.0)
    try:
        swap = psutil.swap_memory()
        return SwapMetrics(total=int(swap.total), used=int(swap.used), percent=round(float(swap.percent), 2))
    except (AttributeError, OSError) as exc:
        logger.warning("Could not read swap metrics: %s", exc)
        return SwapMetrics(total=0, used=0, percent=0.0)


def _fallback_mountpoint() -> str:
    if os.name == "nt":
        return f"{os.getenv('SystemDrive', 'C:')}\\"
    return "/"


def _get_disk_metrics(mountpoint: str) -> DiskMetrics:
    resolved_mountpoint = mountpoint or _fallback_mountpoint()
    if psutil is None:
        return DiskMetrics(total=0, used=0, free=0, percent=0.0, mountpoint=resolved_mountpoint)

    try:
        disk = psutil.disk_usage(resolved_mountpoint)
    except (AttributeError, OSError, PermissionError) as exc:
        fallback = _fallback_mountpoint()
        logger.warning("Could not read disk metrics from %s: %s. Falling back to %s.", resolved_mountpoint, exc, fallback)
        resolved_mountpoint = fallback
        try:
            disk = psutil.disk_usage(resolved_mountpoint)
        except (AttributeError, OSError, PermissionError) as fallback_exc:
            logger.warning("Could not read fallback disk metrics: %s", fallback_exc)
            return DiskMetrics(total=0, used=0, free=0, percent=0.0, mountpoint=resolved_mountpoint)

    return DiskMetrics(
        total=int(disk.total),
        used=int(disk.used),
        free=int(disk.free),
        percent=round(float(disk.percent), 2),
        mountpoint=resolved_mountpoint,
    )


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
        health=_build_disk_health(percent=percent, available=available, read_only=read_only, reason=reason),
    )


def _is_relevant_partition(partition_mountpoint: str, partition_fstype: str) -> bool:
    mountpoint = partition_mountpoint.strip()
    fstype = partition_fstype.strip().lower()
    if not mountpoint:
        return False
    if fstype in IGNORED_FSTYPES:
        return False
    if os.name != "nt" and mountpoint != "/" and mountpoint.startswith(IGNORED_MOUNT_PREFIXES):
        return False
    return True


def _collect_partition_disk_metrics() -> list[DiskDeviceMetrics]:
    if psutil is None:
        return []

    try:
        partitions = psutil.disk_partitions(all=False)
    except (AttributeError, OSError) as exc:
        logger.warning("Could not list disk partitions: %s", exc)
        return []

    disks_by_mountpoint: dict[str, DiskDeviceMetrics] = {}
    for partition in partitions:
        mountpoint = str(getattr(partition, "mountpoint", "") or "")
        fstype = str(getattr(partition, "fstype", "") or "unknown")
        if not _is_relevant_partition(mountpoint, fstype):
            continue

        device = str(getattr(partition, "device", "") or "unknown")
        options = str(getattr(partition, "opts", "") or "")
        read_only = "ro" in _mount_options_set(options)

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
                reason=f"Metrics unavailable: {exc}",
            )

        existing = disks_by_mountpoint.get(mountpoint)
        if existing is None or (not existing.available and disk_metric.available):
            disks_by_mountpoint[mountpoint] = disk_metric

    return list(disks_by_mountpoint.values())


def _get_disks_metrics(mountpoint: str, primary_disk: DiskMetrics) -> list[DiskDeviceMetrics]:
    primary_mountpoint = primary_disk.mountpoint or mountpoint or _fallback_mountpoint()

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

    disks = _collect_partition_disk_metrics()
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


def _get_network_metrics() -> NetworkMetrics:
    if psutil is None:
        return NetworkMetrics(bytes_sent=0, bytes_recv=0, packets_sent=0, packets_recv=0)

    try:
        network = psutil.net_io_counters()
        if network is None:
            raise ValueError("net_io_counters returned None")
        return NetworkMetrics(
            bytes_sent=int(network.bytes_sent),
            bytes_recv=int(network.bytes_recv),
            packets_sent=int(network.packets_sent),
            packets_recv=int(network.packets_recv),
        )
    except (AttributeError, OSError, ValueError) as exc:
        logger.warning("Could not read network metrics: %s", exc)
        return NetworkMetrics(bytes_sent=0, bytes_recv=0, packets_sent=0, packets_recv=0)
