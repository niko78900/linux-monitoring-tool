from __future__ import annotations

import logging
from typing import TYPE_CHECKING

import discord

if TYPE_CHECKING:
    from discord_bot import MonitoringDiscordBot

logger = logging.getLogger("linux_monitoring.bot")


async def resolve_alert_channel(bot: MonitoringDiscordBot) -> discord.abc.Messageable | None:
    return await resolve_channel(bot, bot.config.discord_channel_id)


async def resolve_channel(bot: MonitoringDiscordBot, channel_id: int) -> discord.abc.Messageable | None:
    channel = bot.get_channel(channel_id)
    if channel is None:
        try:
            channel = await bot.fetch_channel(channel_id)
        except discord.HTTPException as exc:
            logger.warning("Could not fetch channel %s: %s", channel_id, exc)
            return None

    if not hasattr(channel, "send"):
        logger.warning("Configured channel %s is not send-capable.", channel_id)
        return None
    return channel


async def safe_send_embed(
    *,
    channel: discord.abc.Messageable,
    embed: discord.Embed,
    context: str,
) -> bool:
    try:
        await channel.send(embed=embed)
    except (discord.Forbidden, discord.NotFound) as exc:
        logger.warning("Cannot send embed (%s): %s", context, exc)
        return False
    except discord.HTTPException as exc:
        logger.warning("Discord API error while sending embed (%s): %s", context, exc)
        return False
    return True
