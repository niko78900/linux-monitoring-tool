from __future__ import annotations

import platform

from app.core.utils import format_duration, utc_now
from app.models.system import SystemResponse
from app.services.system.base_metrics import (
    get_boot_time,
    get_cpu_metrics,
    get_disk_metrics,
    get_hostname,
    get_memory_metrics,
    get_platform_info,
    get_swap_metrics,
)
from app.services.system.network_metrics import get_network_metrics
from app.services.system.specs_metrics import get_system_specs
from app.services.system.storage_metrics import (
    get_disks_metrics,
    get_physical_disks_metrics,
    get_raid_arrays_metrics,
)


def get_system_metrics(mountpoint: str) -> SystemResponse:
    now = utc_now()
    boot_time = get_boot_time(now)
    uptime_seconds = max(0, int((now - boot_time).total_seconds()))
    primary_disk = get_disk_metrics(mountpoint)
    raid_arrays = get_raid_arrays_metrics()
    memory_metrics = get_memory_metrics()
    swap_metrics = get_swap_metrics()
    cpu_metrics = get_cpu_metrics()

    return SystemResponse(
        hostname=get_hostname(),
        os=get_platform_info(),
        kernel_version=platform.release(),
        specs=get_system_specs(memory_metrics=memory_metrics, swap_metrics=swap_metrics, cpu_metrics=cpu_metrics),
        uptime_seconds=uptime_seconds,
        uptime_human=format_duration(uptime_seconds),
        boot_time=boot_time,
        cpu=cpu_metrics,
        memory=memory_metrics,
        swap=swap_metrics,
        disk=primary_disk,
        disks=get_disks_metrics(mountpoint, primary_disk, raid_arrays),
        raid_arrays=raid_arrays,
        physical_disks=get_physical_disks_metrics(raid_arrays),
        network=get_network_metrics(),
    )
