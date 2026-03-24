from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Literal

from config import BotConfig

AlertSeverity = Literal["warning", "critical"]


@dataclass(frozen=True)
class Alert:
    key: str
    title: str
    message: str
    severity: AlertSeverity


def evaluate_alerts(
    *,
    config: BotConfig,
    health: dict[str, Any] | None,
    summary: dict[str, Any] | None,
    system: dict[str, Any] | None,
    gpu: dict[str, Any] | None,
    docker: dict[str, Any] | None,
    backend_error: str | None = None,
    endpoint_errors: dict[str, str] | None = None,
) -> list[Alert]:
    if backend_error:
        return [
            Alert(
                key="backend-unavailable",
                title="Monitoring API unavailable",
                message=backend_error,
                severity="critical",
            )
        ]

    alerts: list[Alert] = []
    endpoint_errors = endpoint_errors or {}

    if health is not None and str(health.get("status", "")).lower() != "ok":
        alerts.append(
            Alert(
                key="backend-health",
                title="Backend health check failed",
                message=f"/api/health status is '{health.get('status')}'.",
                severity="critical",
            )
        )

    for endpoint_name in sorted(endpoint_errors):
        message = endpoint_errors[endpoint_name]
        alerts.append(
            Alert(
                key=f"endpoint-error:{endpoint_name}",
                title=f"{endpoint_name} endpoint error",
                message=message,
                severity="warning",
            )
        )

    if summary is not None:
        alerts.extend(_summary_threshold_alerts(summary=summary, config=config))

    if system is not None:
        alerts.extend(_system_alerts(system=system, config=config))

    if gpu is not None:
        alerts.extend(_gpu_alerts(gpu=gpu, config=config))

    if docker is not None and config.enable_docker_alerts:
        alerts.extend(_docker_alerts(docker=docker))

    alerts.sort(key=lambda item: item.key)
    return alerts


def _summary_threshold_alerts(*, summary: dict[str, Any], config: BotConfig) -> list[Alert]:
    alerts: list[Alert] = []

    cpu = _to_float(summary.get("cpu_percent"))
    if cpu is not None and cpu >= config.cpu_alert_threshold:
        alerts.append(
            _threshold_alert(
                key="cpu-usage",
                title="CPU usage high",
                value=cpu,
                threshold=config.cpu_alert_threshold,
                unit="%",
            )
        )

    memory = _to_float(summary.get("memory_percent"))
    if memory is not None and memory >= config.memory_alert_threshold:
        alerts.append(
            _threshold_alert(
                key="memory-usage",
                title="Memory usage high",
                value=memory,
                threshold=config.memory_alert_threshold,
                unit="%",
            )
        )

    return alerts


def _system_alerts(*, system: dict[str, Any], config: BotConfig) -> list[Alert]:
    alerts: list[Alert] = []

    disks = system.get("disks")
    if isinstance(disks, list):
        for disk in disks:
            if not isinstance(disk, dict):
                continue
            identifier = str(disk.get("mountpoint") or disk.get("device") or "unknown")
            percent = _to_float(disk.get("percent"))
            if percent is not None and percent >= config.disk_alert_threshold:
                alerts.append(
                    _threshold_alert(
                        key=f"disk-usage:{identifier}",
                        title="Disk usage high",
                        value=percent,
                        threshold=config.disk_alert_threshold,
                        unit="%",
                        context=identifier,
                    )
                )

            health = disk.get("health")
            alerts.extend(
                _health_status_alerts(
                    health=health,
                    key=f"disk-health:{identifier}",
                    title="Disk health issue",
                    context=identifier,
                )
            )

    physical_disks = system.get("physical_disks")
    if isinstance(physical_disks, list):
        for physical_disk in physical_disks:
            if not isinstance(physical_disk, dict):
                continue
            identifier = str(physical_disk.get("device") or physical_disk.get("name") or "unknown")
            health = physical_disk.get("health")
            alerts.extend(
                _health_status_alerts(
                    health=health,
                    key=f"physical-disk-health:{identifier}",
                    title="Physical disk health issue",
                    context=identifier,
                )
            )

    if config.enable_raid_alerts:
        raid_arrays = system.get("raid_arrays")
        if isinstance(raid_arrays, list):
            for raid in raid_arrays:
                if not isinstance(raid, dict):
                    continue
                identifier = str(raid.get("name") or raid.get("device") or "unknown")
                health = raid.get("health")
                alerts.extend(
                    _health_status_alerts(
                        health=health,
                        key=f"raid-health:{identifier}",
                        title="RAID health issue",
                        context=identifier,
                    )
                )

    return alerts


def _gpu_alerts(*, gpu: dict[str, Any], config: BotConfig) -> list[Alert]:
    if not bool(gpu.get("available")):
        return []

    temp_c = _to_float(gpu.get("temperature_c"))
    if temp_c is None or temp_c < config.gpu_temp_alert_threshold:
        return []

    return [
        _threshold_alert(
            key="gpu-temperature",
            title="GPU temperature high",
            value=temp_c,
            threshold=config.gpu_temp_alert_threshold,
            unit="C",
        )
    ]


def _docker_alerts(*, docker: dict[str, Any]) -> list[Alert]:
    if bool(docker.get("docker_available")):
        return []
    reason = str(docker.get("reason") or "Docker endpoint marked unavailable.")
    return [
        Alert(
            key="docker-unavailable",
            title="Docker telemetry unavailable",
            message=reason,
            severity="warning",
        )
    ]


def _health_status_alerts(*, health: Any, key: str, title: str, context: str) -> list[Alert]:
    if not isinstance(health, dict):
        return []

    status = str(health.get("status") or "unknown").lower()
    if status in {"healthy"}:
        return []

    reason = str(health.get("reason") or "No reason provided.")
    severity = "critical" if status == "critical" else "warning"

    return [
        Alert(
            key=key,
            title=title,
            message=f"{context}: {reason}",
            severity=severity,
        )
    ]


def _threshold_alert(
    *,
    key: str,
    title: str,
    value: float,
    threshold: float,
    unit: str,
    context: str | None = None,
) -> Alert:
    severity: AlertSeverity = "critical" if value >= max(95.0, threshold + 10.0) else "warning"
    value_text = _format_number(value)
    threshold_text = _format_number(threshold)

    prefix = f"{context}: " if context else ""
    message = f"{prefix}{value_text}{unit} is above threshold ({threshold_text}{unit})."
    return Alert(key=key, title=title, message=message, severity=severity)


def _to_float(value: Any) -> float | None:
    if value is None:
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _format_number(value: float) -> str:
    if value.is_integer():
        return str(int(value))
    return f"{value:.1f}"
