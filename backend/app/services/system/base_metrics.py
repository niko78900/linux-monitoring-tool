from __future__ import annotations

import logging
import os
import platform
import socket
from datetime import datetime

from app.core.utils import to_utc_datetime
from app.models.system import CpuMetrics, DiskMetrics, LoadAverage, MemoryMetrics, PlatformInfo, SwapMetrics

try:
    import psutil
except ImportError:  # pragma: no cover - handled at runtime
    psutil = None  # type: ignore[assignment]

logger = logging.getLogger(__name__)


def get_hostname() -> str:
    try:
        return socket.gethostname()
    except OSError as exc:
        logger.warning("Could not read hostname: %s", exc)
        return "unknown"


def get_platform_info() -> PlatformInfo:
    return PlatformInfo(
        system=platform.system(),
        release=platform.release(),
        version=platform.version(),
        machine=platform.machine(),
        platform=platform.platform(),
    )


def get_boot_time(now: datetime) -> datetime:
    if psutil is None:
        return now
    try:
        return to_utc_datetime(psutil.boot_time())
    except (AttributeError, OSError) as exc:
        logger.warning("Could not read boot time: %s", exc)
        return now


def get_cpu_metrics() -> CpuMetrics:
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


def get_memory_metrics() -> MemoryMetrics:
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


def get_swap_metrics() -> SwapMetrics:
    if psutil is None:
        return SwapMetrics(total=0, used=0, percent=0.0)
    try:
        swap = psutil.swap_memory()
        return SwapMetrics(total=int(swap.total), used=int(swap.used), percent=round(float(swap.percent), 2))
    except (AttributeError, OSError) as exc:
        logger.warning("Could not read swap metrics: %s", exc)
        return SwapMetrics(total=0, used=0, percent=0.0)


def fallback_mountpoint() -> str:
    if os.name == "nt":
        return f"{os.getenv('SystemDrive', 'C:')}\\"
    return "/"


def get_disk_metrics(mountpoint: str) -> DiskMetrics:
    resolved_mountpoint = mountpoint or fallback_mountpoint()
    if psutil is None:
        return DiskMetrics(total=0, used=0, free=0, percent=0.0, mountpoint=resolved_mountpoint)

    try:
        disk = psutil.disk_usage(resolved_mountpoint)
    except (AttributeError, OSError, PermissionError) as exc:
        fallback = fallback_mountpoint()
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
