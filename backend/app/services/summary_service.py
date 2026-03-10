from __future__ import annotations

from app.core.utils import format_duration, utc_now
from app.models.summary import SummaryResponse
from app.services.docker_service import get_docker_summary
from app.services.gpu_service import get_gpu_metrics
from app.services.system.base_metrics import (
    get_boot_time,
    get_cpu_metrics,
    get_disk_metrics,
    get_hostname,
    get_memory_metrics,
)


def get_summary_metrics(mountpoint: str) -> SummaryResponse:
    now = utc_now()
    boot_time = get_boot_time(now)
    uptime_seconds = max(0, int((now - boot_time).total_seconds()))
    cpu = get_cpu_metrics()
    memory = get_memory_metrics()
    disk = get_disk_metrics(mountpoint)
    gpu = get_gpu_metrics()
    docker_summary = get_docker_summary()

    return SummaryResponse(
        hostname=get_hostname(),
        uptime_human=format_duration(uptime_seconds),
        cpu_percent=cpu.usage_percent,
        memory_percent=memory.percent,
        disk_percent=disk.percent,
        gpu_available=gpu.available,
        gpu_utilization_percent=gpu.utilization_percent if gpu.available else None,
        gpu_temp_c=gpu.temperature_c if gpu.available else None,
        docker_available=docker_summary.docker_available,
        running_containers=docker_summary.running_containers,
    )
