from __future__ import annotations

import logging
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from discord_bot import MonitoringDiscordBot

logger = logging.getLogger("linux_monitoring.bot")


async def run_status_autopost(bot: MonitoringDiscordBot) -> None:
    if bot.status_autopost_channel_id is None:
        return
    if not bot._is_status_autopost_due():
        return
    if not bot.status_autopost_next_should_send:
        bot._reset_status_autopost_deadline()
        return

    channel = await bot._resolve_channel(bot.status_autopost_channel_id)
    if channel is None:
        bot._schedule_status_autopost_retry()
        return
    channel_guild = getattr(channel, "guild", None)
    channel_guild_id = getattr(channel_guild, "id", None)
    if bot.status_autopost_guild_id is not None and channel_guild_id != bot.status_autopost_guild_id:
        logger.warning(
            "Skipping status autopost due to guild mismatch: expected=%s actual=%s",
            bot.status_autopost_guild_id,
            channel_guild_id,
        )
        bot._schedule_status_autopost_retry()
        return

    embed = await bot._build_status_embed()
    sent = await bot._safe_send_embed(channel=channel, embed=embed, context="status_autopost")
    if sent:
        bot._reset_status_autopost_deadline()
        logger.info(
            "Posted scheduled status to channel_id=%s; next run at %s",
            bot.status_autopost_channel_id,
            bot.status_autopost_next_run_at.isoformat() if bot.status_autopost_next_run_at else "unknown",
        )
    else:
        bot._schedule_status_autopost_retry()
