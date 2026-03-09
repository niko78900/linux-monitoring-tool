from __future__ import annotations

from app.models.summary import SummaryResponse
from app.services.docker_service import get_docker_summary
from app.services.gpu_service import get_gpu_metrics
from app.services.system_service import get_system_metrics


def get_summary_metrics(mountpoint: str) -> SummaryResponse:
    system = get_system_metrics(mountpoint)
    gpu = get_gpu_metrics()
    docker_summary = get_docker_summary()

    return SummaryResponse(
        hostname=system.hostname,
        uptime_human=system.uptime_human,
        cpu_percent=system.cpu.usage_percent,
        memory_percent=system.memory.percent,
        disk_percent=system.disk.percent,
        gpu_available=gpu.available,
        gpu_utilization_percent=gpu.utilization_percent if gpu.available else None,
        gpu_temp_c=gpu.temperature_c if gpu.available else None,
        docker_available=docker_summary.docker_available,
        running_containers=docker_summary.running_containers,
    )
