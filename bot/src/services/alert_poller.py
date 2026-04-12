from __future__ import annotations

import asyncio
import logging
from typing import TYPE_CHECKING, Any

from alert_rules import evaluate_alerts
from formatters import format_alert_embed, format_recovery_embed
from monitoring_client import MonitoringAPIError

if TYPE_CHECKING:
    from discord_bot import MonitoringDiscordBot

logger = logging.getLogger("linux_monitoring.bot")


async def run_alert_polling(bot: MonitoringDiscordBot) -> None:
    channel = await bot._resolve_alert_channel()
    if channel is None:
        return

    health_payload: dict[str, Any] | None = None
    summary_payload: dict[str, Any] | None = None
    system_payload: dict[str, Any] | None = None
    gpu_payload: dict[str, Any] | None = None
    docker_payload: dict[str, Any] | None = None
    backend_error: str | None = None
    endpoint_errors: dict[str, str] = {}

    try:
        health_payload = await bot.monitoring_client.fetch_health()
    except MonitoringAPIError as exc:
        logger.warning("Health polling failed: %s", exc)
        backend_error = "health endpoint is unavailable."

    if backend_error is None:
        endpoints = {
            "summary": bot.monitoring_client.fetch_summary(),
            "system": bot.monitoring_client.fetch_system(),
            "gpu": bot.monitoring_client.fetch_gpu(),
            "docker": bot.monitoring_client.fetch_docker(),
        }
        results = await asyncio.gather(*endpoints.values(), return_exceptions=True)
        for endpoint_name, result in zip(endpoints.keys(), results):
            if isinstance(result, Exception):
                logger.warning("Polling failed for endpoint %s: %s", endpoint_name, result)
                endpoint_errors[endpoint_name] = f"{endpoint_name} endpoint is unavailable."
                continue

            if endpoint_name == "summary":
                summary_payload = result
            elif endpoint_name == "system":
                system_payload = result
            elif endpoint_name == "gpu":
                gpu_payload = result
            elif endpoint_name == "docker":
                docker_payload = result

    active_alerts = evaluate_alerts(
        config=bot.config,
        health=health_payload,
        summary=summary_payload,
        system=system_payload,
        gpu=gpu_payload,
        docker=docker_payload,
        backend_error=backend_error,
        endpoint_errors=endpoint_errors,
    )

    new_alerts, recoveries = bot.alert_state.transition(active_alerts)
    if not new_alerts and not recoveries:
        return
    bot._save_alert_state()

    for alert in new_alerts:
        await bot._safe_send_embed(
            channel=channel,
            embed=format_alert_embed(alert),
            context=f"alert:{alert.key}",
        )
    for recovery in recoveries:
        await bot._safe_send_embed(
            channel=channel,
            embed=format_recovery_embed(recovery),
            context=f"recovery:{recovery.key}",
        )
