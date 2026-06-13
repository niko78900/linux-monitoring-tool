from __future__ import annotations

from app.core.config import Settings
from app.models.docker import DockerSummaryResponse
from app.models.gpu import GPUResponse
from app.models.system import DiskHealth, RaidHealth, SystemResponse

from .models import AlertCandidate, AlertSeverity


def evaluate_alerts(
    *,
    settings: Settings,
    system: SystemResponse | None,
    gpu: GPUResponse | None,
    docker: DockerSummaryResponse | None,
) -> list[AlertCandidate]:
    alerts: list[AlertCandidate] = []

    if system is not None:
        alerts.extend(_system_alerts(settings=settings, system=system))
    if gpu is not None:
        alerts.extend(_gpu_alerts(settings=settings, gpu=gpu))
    if docker is not None and not docker.docker_available:
        alerts.append(
            AlertCandidate(
                key="docker-unavailable",
                category="docker",
                severity="warning",
                title="Docker telemetry unavailable",
                message="Docker summary could not be collected.",
                mobile_scope=False,
            )
        )

    alerts.sort(key=lambda item: item.key)
    return alerts


def _system_alerts(*, settings: Settings, system: SystemResponse) -> list[AlertCandidate]:
    alerts: list[AlertCandidate] = []

    cpu = system.cpu.usage_percent
    if cpu >= settings.cpu_alert_threshold:
        alerts.append(
            _threshold_alert(
                key="cpu-usage",
                category="cpu",
                title="CPU usage high",
                value=cpu,
                threshold=settings.cpu_alert_threshold,
                unit="%",
                route="/overview",
                mobile_scope=True,
            )
        )

    memory = system.memory.percent
    if memory >= settings.memory_alert_threshold:
        alerts.append(
            _threshold_alert(
                key="memory-usage",
                category="memory",
                title="Memory usage high",
                value=memory,
                threshold=settings.memory_alert_threshold,
                unit="%",
                route="/overview",
                mobile_scope=True,
            )
        )

    for disk in system.disks:
        identifier = disk.mountpoint or disk.device or "unknown"
        label = _friendly_storage_name(identifier)
        if disk.percent >= settings.disk_alert_threshold:
            alerts.append(
                _threshold_alert(
                    key=f"disk-usage:{identifier}",
                    category="disk",
                    title="Disk usage high",
                    value=disk.percent,
                    threshold=settings.disk_alert_threshold,
                    unit="%",
                    context=label,
                    route="/storage",
                    mobile_scope=True,
                )
            )

        alerts.extend(
            _health_alerts(
                health=disk.health,
                key=f"disk-health:{identifier}",
                category="disk-health",
                title="Disk health issue",
                context=label,
            )
        )

    for physical_disk in system.physical_disks:
        identifier = physical_disk.device or physical_disk.name or "unknown"
        label = physical_disk.model or identifier
        alerts.extend(
            _health_alerts(
                health=physical_disk.health,
                key=f"physical-disk-health:{identifier}",
                category="physical-disk-health",
                title="Physical disk health issue",
                context=label,
            )
        )

    for raid in system.raid_arrays:
        identifier = raid.name or raid.device or "unknown"
        alerts.extend(
            _health_alerts(
                health=raid.health,
                key=f"raid-health:{identifier}",
                category="raid-health",
                title="RAID health issue",
                context=identifier,
            )
        )

    return alerts


def _gpu_alerts(*, settings: Settings, gpu: GPUResponse) -> list[AlertCandidate]:
    if not gpu.available:
        return []

    alerts: list[AlertCandidate] = []
    utilization = gpu.utilization_percent
    if utilization is not None and utilization >= settings.gpu_usage_alert_threshold:
        alerts.append(
            _threshold_alert(
                key="gpu-usage",
                category="gpu",
                title="GPU usage high",
                value=utilization,
                threshold=settings.gpu_usage_alert_threshold,
                unit="%",
                route="/gpu",
                mobile_scope=True,
            )
        )

    temperature = gpu.temperature_c
    if temperature is not None and temperature >= settings.gpu_temp_alert_threshold:
        alerts.append(
            _threshold_alert(
                key="gpu-temperature",
                category="gpu-temperature",
                title="GPU temperature high",
                value=temperature,
                threshold=settings.gpu_temp_alert_threshold,
                unit="C",
                route="/gpu",
                mobile_scope=False,
            )
        )

    return alerts


def _threshold_alert(
    *,
    key: str,
    category: str,
    title: str,
    value: float,
    threshold: float,
    unit: str,
    context: str | None = None,
    route: str | None = None,
    mobile_scope: bool = False,
) -> AlertCandidate:
    severity: AlertSeverity = "critical" if value >= max(95.0, threshold + 10.0) else "warning"
    prefix = f"{context}: " if context else ""
    message = f"{prefix}{_format_number(value)}{unit} is above threshold ({_format_number(threshold)}{unit})."
    return AlertCandidate(
        key=key,
        category=category,
        severity=severity,
        title=title,
        message=message,
        route=route,
        mobile_scope=mobile_scope,
    )


def _health_alerts(
    *,
    health: DiskHealth | RaidHealth,
    key: str,
    category: str,
    title: str,
    context: str,
) -> list[AlertCandidate]:
    if health.status == "healthy":
        return []
    severity: AlertSeverity = "critical" if health.status == "critical" else "warning"
    return [
        AlertCandidate(
            key=key,
            category=category,
            severity=severity,
            title=title,
            message=f"{context}: {health.reason}",
            mobile_scope=False,
        )
    ]


def _friendly_storage_name(target: str) -> str:
    normalized = target.strip()
    if normalized == "/":
        return "Primary Storage"
    if normalized == "/mnt/warm":
        return "Warm Storage"
    if normalized == "/mnt/storage":
        return "Cold Storage"
    if normalized.startswith("/mnt/"):
        return normalized.removeprefix("/mnt/").replace("-", " ").title()
    return normalized or "Storage"


def _format_number(value: float) -> str:
    numeric = float(value)
    if numeric.is_integer():
        return str(int(numeric))
    return f"{numeric:.1f}"
