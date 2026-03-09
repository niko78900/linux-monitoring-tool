from __future__ import annotations

import logging
import os
import platform
import socket
from datetime import datetime

from app.core.utils import format_duration, to_utc_datetime, utc_now
from app.models.system import (
    CpuMetrics,
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


def get_system_metrics(mountpoint: str) -> SystemResponse:
    now = utc_now()
    boot_time = _get_boot_time(now)
    uptime_seconds = max(0, int((now - boot_time).total_seconds()))

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
        disk=_get_disk_metrics(mountpoint),
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
