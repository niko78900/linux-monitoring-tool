from __future__ import annotations

import logging
from typing import TYPE_CHECKING, Any

from alert_rules import Alert
from formatters import (
    format_alert_embed,
    format_alert_event_embed,
    format_recovery_embed,
)
from monitoring_client import MonitoringAPIError

if TYPE_CHECKING:
    from discord_bot import MonitoringDiscordBot

logger = logging.getLogger("linux_monitoring.bot")


async def run_alert_polling(bot: MonitoringDiscordBot) -> None:
    channel = await bot._resolve_alert_channel()
    if channel is None:
        logger.warning("Alert channel is unavailable; backend alert cursor will not advance.")
        return

    try:
        await bot.monitoring_client.fetch_health()
        await _send_backend_recovery_if_needed(bot, channel)
        last_event_id = await _ensure_cursor(bot)
        events_payload = await bot.monitoring_client.fetch_alert_events(
            after_id=last_event_id,
            limit=100,
        )
    except MonitoringAPIError as exc:
        logger.warning("Backend alert feed polling failed: %s", exc)
        await _send_backend_unreachable_if_needed(bot, channel, exc)
        return

    raw_events = events_payload.get("events")
    events: list[dict[str, Any]] = [
        item for item in raw_events if isinstance(item, dict)
    ] if isinstance(raw_events, list) else []

    for event in events:
        event_id = _event_id(event)
        if event_id is None:
            continue
        sent = await bot._safe_send_embed(
            channel=channel,
            embed=format_alert_event_embed(event),
            context=f"backend-alert-event:{event_id}",
        )
        if not sent:
            return
        bot.alert_cursor.save(event_id)


async def _ensure_cursor(bot: MonitoringDiscordBot) -> int:
    if bot.alert_cursor.last_event_id is not None:
        return bot.alert_cursor.last_event_id

    if bot.config.discord_alert_replay_on_first_start:
        bot.alert_cursor.save(0)
        return 0

    status_payload = await bot.monitoring_client.fetch_alert_status()
    latest = _int(status_payload.get("latest_event_id"))
    bot.alert_cursor.save(latest)
    return latest


async def _send_backend_unreachable_if_needed(
    bot: MonitoringDiscordBot,
    channel: Any,
    exc: Exception,
) -> None:
    alert = Alert(
        key="backend-unavailable",
        title="Monitoring API unavailable",
        message=f"Backend alert event feed is unavailable: {exc}",
        severity="critical",
    )
    alerts, _ = bot.backend_unreachable_state.transition([alert])
    for item in alerts:
        await bot._safe_send_embed(
            channel=channel,
            embed=format_alert_embed(item),
            context=f"alert:{item.key}",
        )


async def _send_backend_recovery_if_needed(
    bot: MonitoringDiscordBot,
    channel: Any,
) -> None:
    _, recoveries = bot.backend_unreachable_state.transition([])
    for recovery in recoveries:
        await bot._safe_send_embed(
            channel=channel,
            embed=format_recovery_embed(recovery),
            context=f"recovery:{recovery.key}",
        )


def _event_id(event: dict[str, Any]) -> int | None:
    value = event.get("event_id")
    try:
        parsed = int(value)
    except (TypeError, ValueError):
        return None
    return parsed if parsed >= 0 else None


def _int(value: object) -> int:
    try:
        return max(0, int(value))
    except (TypeError, ValueError):
        return 0
