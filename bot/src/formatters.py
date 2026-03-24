from __future__ import annotations

from typing import Any

import discord

from alert_rules import Alert
from alert_state import RecoveryNotice


def format_api_error_embed(message: str) -> discord.Embed:
    return discord.Embed(
        title="Monitoring API error",
        description=message,
        color=discord.Color.red(),
        timestamp=discord.utils.utcnow(),
    )


def format_status_embed(
    *,
    system: dict[str, Any],
    gpu: dict[str, Any] | None = None,
    gpu_error: str | None = None,
) -> discord.Embed:
    hostname = str(system.get("hostname") or "unknown")
    cpu = system.get("cpu") if isinstance(system.get("cpu"), dict) else {}
    memory = system.get("memory") if isinstance(system.get("memory"), dict) else {}
    disks = _extract_status_disks(system)

    cpu_usage_raw = _to_float(cpu.get("usage_percent"))
    ram_percent_raw = _to_float(memory.get("percent"))
    disk_percents = [_to_float(item.get("percent")) for item in disks]
    disk_percent_max = max([value for value in disk_percents if value is not None], default=None)

    embed = discord.Embed(
        title=f"Status - {hostname}",
        color=_status_color(cpu_usage_raw, ram_percent_raw, disk_percent_max),
        timestamp=discord.utils.utcnow(),
    )

    embed.add_field(name="Storage (% full)", value=_format_storage_lines(disks), inline=False)
    embed.add_field(name="CPU Usage", value=_format_percent(cpu.get("usage_percent")), inline=True)
    embed.add_field(name="GPU Usage", value=_format_gpu_usage(gpu=gpu, gpu_error=gpu_error), inline=True)
    embed.add_field(name="RAM", value=_format_ram_usage(memory), inline=True)
    embed.add_field(name="CPU Temp", value=_format_numeric(cpu.get("temperature_c"), "C"), inline=True)
    embed.add_field(name="GPU Temp", value=_format_gpu_temp(gpu=gpu, gpu_error=gpu_error), inline=True)
    embed.add_field(name="Uptime", value=str(system.get("uptime_human") or "n/a"), inline=True)

    if gpu_error:
        embed.set_footer(text="GPU details partially unavailable: /api/gpu request failed.")

    return embed


def format_health_embed(health: dict[str, Any]) -> discord.Embed:
    status = str(health.get("status") or "unknown")
    color = discord.Color.green() if status.lower() == "ok" else discord.Color.red()
    embed = discord.Embed(
        title="Backend Health",
        color=color,
        timestamp=discord.utils.utcnow(),
    )
    embed.add_field(name="Status", value=status, inline=True)
    embed.add_field(name="App", value=str(health.get("app_name") or "n/a"), inline=True)
    embed.add_field(name="Version", value=str(health.get("version") or "n/a"), inline=True)
    embed.add_field(name="Timestamp", value=str(health.get("timestamp") or "n/a"), inline=False)
    return embed


def format_docker_embed(docker: dict[str, Any]) -> discord.Embed:
    available = bool(docker.get("docker_available"))
    color = discord.Color.green() if available else discord.Color.orange()
    embed = discord.Embed(
        title="Docker",
        color=color,
        timestamp=discord.utils.utcnow(),
    )

    if not available:
        embed.description = str(docker.get("reason") or "Docker telemetry unavailable.")
        return embed

    container_count = docker.get("container_count")
    embed.add_field(name="Container Count", value=str(container_count), inline=True)

    containers = docker.get("containers")
    if not isinstance(containers, list) or not containers:
        embed.add_field(name="Containers", value="No containers reported.", inline=False)
        return embed

    lines: list[str] = []
    for container in containers[:8]:
        if not isinstance(container, dict):
            continue
        name = str(container.get("name") or "unknown")
        state = str(container.get("state") or "unknown")
        image = str(container.get("image") or "unknown")
        lines.append(f"`{name}` - {state} ({image})")
    if len(containers) > 8:
        lines.append(f"...and {len(containers) - 8} more")

    embed.add_field(name="Containers", value="\n".join(lines) or "No containers reported.", inline=False)
    return embed


def format_gpu_embed(gpu: dict[str, Any]) -> discord.Embed:
    available = bool(gpu.get("available"))
    color = discord.Color.green() if available else discord.Color.orange()
    embed = discord.Embed(
        title="GPU",
        color=color,
        timestamp=discord.utils.utcnow(),
    )
    if not available:
        embed.description = str(gpu.get("reason") or "GPU telemetry unavailable.")
        return embed

    embed.add_field(name="Name", value=str(gpu.get("name") or "n/a"), inline=False)
    embed.add_field(name="Temperature", value=_format_numeric(gpu.get("temperature_c"), "C"), inline=True)
    embed.add_field(name="Utilization", value=_format_percent(gpu.get("utilization_percent")), inline=True)
    embed.add_field(
        name="Memory",
        value=_format_memory_line(
            total_mb=gpu.get("memory_total_mb"),
            used_mb=gpu.get("memory_used_mb"),
            free_mb=gpu.get("memory_free_mb"),
        ),
        inline=False,
    )
    embed.add_field(name="Power", value=_format_numeric(gpu.get("power_usage_w"), "W"), inline=True)
    embed.add_field(name="Fan", value=_format_percent(gpu.get("fan_speed_percent")), inline=True)
    embed.add_field(name="Driver", value=str(gpu.get("driver_version") or "n/a"), inline=True)
    return embed


def format_system_embed(system: dict[str, Any]) -> discord.Embed:
    hostname = str(system.get("hostname") or "unknown")
    embed = discord.Embed(
        title=f"System - {hostname}",
        color=discord.Color.blurple(),
        timestamp=discord.utils.utcnow(),
    )
    cpu = system.get("cpu") if isinstance(system.get("cpu"), dict) else {}
    memory = system.get("memory") if isinstance(system.get("memory"), dict) else {}
    disk = system.get("disk") if isinstance(system.get("disk"), dict) else {}

    embed.add_field(name="Uptime", value=str(system.get("uptime_human") or "n/a"), inline=True)
    embed.add_field(name="CPU", value=_format_percent(cpu.get("usage_percent")), inline=True)
    embed.add_field(name="Memory", value=_format_percent(memory.get("percent")), inline=True)
    embed.add_field(name="Primary Disk", value=_format_percent(disk.get("percent")), inline=True)

    disks = system.get("disks")
    raid_arrays = system.get("raid_arrays")
    physical_disks = system.get("physical_disks")
    disk_issues = _count_non_healthy(disks)
    raid_issues = _count_non_healthy(raid_arrays)
    physical_issues = _count_non_healthy(physical_disks)

    embed.add_field(name="Disk Issues", value=str(disk_issues), inline=True)
    embed.add_field(name="RAID Issues", value=str(raid_issues), inline=True)
    embed.add_field(name="Physical Disk Issues", value=str(physical_issues), inline=True)

    disk_lines: list[str] = []
    if isinstance(disks, list):
        sorted_disks = sorted(
            [item for item in disks if isinstance(item, dict)],
            key=lambda item: _to_float(item.get("percent")),
            reverse=True,
        )
        for disk_item in sorted_disks[:5]:
            mountpoint = str(disk_item.get("mountpoint") or disk_item.get("device") or "unknown")
            percent = _format_percent(disk_item.get("percent"))
            status = _extract_health_status(disk_item)
            disk_lines.append(f"{mountpoint}: {percent} ({status})")

    embed.add_field(
        name="Top Disk Usage",
        value="\n".join(disk_lines) if disk_lines else "No disk entries.",
        inline=False,
    )
    return embed


def format_alert_embed(alert: Alert) -> discord.Embed:
    color = discord.Color.red() if alert.severity == "critical" else discord.Color.orange()
    embed = discord.Embed(
        title=f"Alert: {alert.title}",
        description=alert.message,
        color=color,
        timestamp=discord.utils.utcnow(),
    )
    embed.add_field(name="Severity", value=alert.severity, inline=True)
    embed.add_field(name="Key", value=alert.key, inline=True)
    return embed


def format_recovery_embed(recovery: RecoveryNotice) -> discord.Embed:
    embed = discord.Embed(
        title=f"Recovered: {recovery.title}",
        description=recovery.message,
        color=discord.Color.green(),
        timestamp=discord.utils.utcnow(),
    )
    embed.add_field(name="Key", value=recovery.key, inline=True)
    embed.add_field(name="Active For", value=f"{recovery.was_active_for_seconds}s", inline=True)
    return embed


def _count_non_healthy(items: Any) -> int:
    if not isinstance(items, list):
        return 0
    count = 0
    for item in items:
        if not isinstance(item, dict):
            continue
        status = _extract_health_status(item)
        if status != "healthy":
            count += 1
    return count


def _extract_health_status(item: dict[str, Any]) -> str:
    health = item.get("health")
    if not isinstance(health, dict):
        return "unknown"
    return str(health.get("status") or "unknown")


def _format_percent(value: Any) -> str:
    numeric = _to_float(value)
    if numeric is None:
        return "n/a"
    return f"{numeric:.1f}%"


def _format_numeric(value: Any, unit: str) -> str:
    numeric = _to_float(value)
    if numeric is None:
        return "n/a"
    return f"{numeric:.1f}{unit}"


def _format_memory_line(*, total_mb: Any, used_mb: Any, free_mb: Any) -> str:
    total = _to_float(total_mb)
    used = _to_float(used_mb)
    free = _to_float(free_mb)
    if total is None:
        return "n/a"
    if used is None or free is None:
        return f"Total: {total:.0f} MB"
    return f"Used: {used:.0f} MB / Free: {free:.0f} MB / Total: {total:.0f} MB"


def _format_ram_usage(memory: dict[str, Any]) -> str:
    used = _to_float(memory.get("used"))
    total = _to_float(memory.get("total"))
    percent = _format_percent(memory.get("percent"))

    if used is None or total is None or total <= 0:
        return f"n/a ({percent} full)"

    return f"{_format_gib(used)}/{_format_gib(total)} GB ({percent} full)"


def _format_gib(value_bytes: float) -> str:
    gib = value_bytes / float(1024**3)
    if gib >= 100:
        return f"{gib:.0f}"
    if gib >= 10:
        return f"{gib:.1f}"
    return f"{gib:.2f}"


def _format_gpu_usage(*, gpu: dict[str, Any] | None, gpu_error: str | None) -> str:
    if gpu_error:
        return "Unavailable"
    if not isinstance(gpu, dict):
        return "n/a"
    if not bool(gpu.get("available")):
        return "Unavailable"
    return _format_percent(gpu.get("utilization_percent"))


def _format_gpu_temp(*, gpu: dict[str, Any] | None, gpu_error: str | None) -> str:
    if gpu_error:
        return "Unavailable"
    if not isinstance(gpu, dict):
        return "n/a"
    if not bool(gpu.get("available")):
        return "Unavailable"
    return _format_numeric(gpu.get("temperature_c"), "C")


def _extract_status_disks(system: dict[str, Any]) -> list[dict[str, Any]]:
    disks = system.get("disks")
    if isinstance(disks, list):
        parsed = [item for item in disks if isinstance(item, dict)]
        if parsed:
            return parsed

    primary_disk = system.get("disk")
    if isinstance(primary_disk, dict):
        return [primary_disk]
    return []


def _format_storage_lines(disks: list[dict[str, Any]]) -> str:
    if not disks:
        return "No storage devices reported."

    sorted_disks = sorted(
        disks,
        key=lambda item: _to_float(item.get("percent")) if _to_float(item.get("percent")) is not None else -1.0,
        reverse=True,
    )

    lines: list[str] = []
    for item in sorted_disks:
        target = str(item.get("mountpoint") or item.get("device") or "unknown")
        percent = _format_percent(item.get("percent"))
        line = f"{target}: {percent} full"
        tentative = "\n".join(lines + [line])
        if len(tentative) > 980:
            break
        lines.append(line)

    remaining = len(sorted_disks) - len(lines)
    if remaining > 0:
        suffix = f"...and {remaining} more"
        if len("\n".join(lines + [suffix])) <= 1024:
            lines.append(suffix)

    return "\n".join(lines)


def _status_color(cpu: float | None, ram: float | None, disk: float | None) -> discord.Color:
    values = [value for value in (cpu, ram, disk) if value is not None]
    if not values:
        return discord.Color.blurple()

    hottest = max(values)
    if hottest >= 90:
        return discord.Color.red()
    if hottest >= 75:
        return discord.Color.orange()
    return discord.Color.green()


def _to_float(value: Any) -> float | None:
    if value is None:
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None
