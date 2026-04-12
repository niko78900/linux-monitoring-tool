from __future__ import annotations

from typing import TYPE_CHECKING, Any

import discord
from discord import app_commands

from bot_constants import (
    STATUS_SCHEDULE_MAX_MINUTES,
    STATUS_SCHEDULE_MAX_WINDOWS,
    STATUS_SCHEDULE_MIN_MINUTES,
    STATUS_SCHEDULE_MODE_FIXED,
    STATUS_SCHEDULE_MODE_WINDOWS,
)
from formatters import format_docker_embed, format_gpu_embed, format_health_embed, format_system_embed
from schedule_policy import TimeWindowRule, format_windows_for_display, parse_windows_spec

if TYPE_CHECKING:
    from discord_bot import MonitoringDiscordBot


def register_slash_commands(bot: MonitoringDiscordBot) -> None:
    command_kwargs: dict[str, Any] = {}
    if bot.guild_object is not None:
        command_kwargs["guild"] = bot.guild_object

    @bot.tree.command(name="status", description="Detailed live status (CPU/GPU/RAM/storage/temps/uptime).", **command_kwargs)
    async def status_command(interaction: discord.Interaction) -> None:
        await interaction.response.defer(thinking=True)
        embed = await bot._build_status_embed()
        await interaction.followup.send(embed=embed)

    @bot.tree.command(
        name="status_schedule",
        description="Enable periodic /status posts in this channel.",
        **command_kwargs,
    )
    @app_commands.describe(interval_minutes="How often to post status updates.")
    async def status_schedule_command(
        interaction: discord.Interaction,
        interval_minutes: app_commands.Range[int, STATUS_SCHEDULE_MIN_MINUTES, STATUS_SCHEDULE_MAX_MINUTES],
    ) -> None:
        await interaction.response.defer(ephemeral=True, thinking=False)

        if not bot._can_manage_schedule(interaction):
            await interaction.followup.send(
                "You need `Manage Server` permission to change scheduled status posts.",
                ephemeral=True,
            )
            return

        if interaction.guild_id is None:
            await interaction.followup.send("This command must be used in a server.", ephemeral=True)
            return
        if bot.config.discord_guild_id is not None and interaction.guild_id != bot.config.discord_guild_id:
            await interaction.followup.send(
                "This bot is configured for a different server. Check `DISCORD_GUILD_ID`.",
                ephemeral=True,
            )
            return
        if interaction.channel_id is None:
            await interaction.followup.send("This command must be used in a server channel.", ephemeral=True)
            return

        channel = await bot._resolve_channel(interaction.channel_id)
        if channel is None:
            await interaction.followup.send("I cannot access this channel.", ephemeral=True)
            return

        embed = await bot._build_status_embed()
        sent = await bot._safe_send_embed(
            channel=channel,
            embed=embed,
            context="status_schedule_test",
        )
        if not sent:
            await interaction.followup.send(
                "I couldn't post a status embed in this channel. Check channel permissions and try again.",
                ephemeral=True,
            )
            return

        bot.status_autopost_channel_id = interaction.channel_id
        bot.status_autopost_guild_id = interaction.guild_id
        bot.status_autopost_mode = STATUS_SCHEDULE_MODE_FIXED
        bot.status_autopost_windows = []
        bot.status_autopost_interval_seconds = int(interval_minutes) * 60
        bot._reset_status_autopost_deadline()
        if not bot.status_autopost.is_running():
            bot.status_autopost.start()
        bot._save_status_schedule_state()

        await interaction.followup.send(
            (
                f"Scheduled status posts every `{interval_minutes}` minute(s) "
                f"in <#{interaction.channel_id}>. First scheduled post will be sent after the interval."
            ),
            ephemeral=True,
        )

    @bot.tree.command(
        name="status_schedule_custom",
        description="Set multiple time windows with custom /status intervals.",
        **command_kwargs,
    )
    @app_commands.describe(
        windows_spec="Format: HH:MM-HH:MM=MINUTES;HH:MM-HH:MM=MINUTES",
    )
    async def status_schedule_custom_command(
        interaction: discord.Interaction,
        windows_spec: str,
    ) -> None:
        await interaction.response.defer(ephemeral=True, thinking=False)

        if not bot._can_manage_schedule(interaction):
            await interaction.followup.send(
                "You need `Manage Server` permission to change scheduled status posts.",
                ephemeral=True,
            )
            return

        if interaction.guild_id is None:
            await interaction.followup.send("This command must be used in a server.", ephemeral=True)
            return
        if bot.config.discord_guild_id is not None and interaction.guild_id != bot.config.discord_guild_id:
            await interaction.followup.send(
                "This bot is configured for a different server. Check `DISCORD_GUILD_ID`.",
                ephemeral=True,
            )
            return
        if interaction.channel_id is None:
            await interaction.followup.send("This command must be used in a server channel.", ephemeral=True)
            return

        try:
            windows = parse_windows_spec(
                windows_spec,
                min_interval_minutes=STATUS_SCHEDULE_MIN_MINUTES,
                max_interval_minutes=STATUS_SCHEDULE_MAX_MINUTES,
                max_rules=STATUS_SCHEDULE_MAX_WINDOWS,
            )
        except ValueError as exc:
            await interaction.followup.send(
                f"Invalid windows spec: {exc}",
                ephemeral=True,
            )
            return

        channel = await bot._resolve_channel(interaction.channel_id)
        if channel is None:
            await interaction.followup.send("I cannot access this channel.", ephemeral=True)
            return

        embed = await bot._build_status_embed()
        sent = await bot._safe_send_embed(
            channel=channel,
            embed=embed,
            context="status_schedule_custom_test",
        )
        if not sent:
            await interaction.followup.send(
                "I couldn't post a status embed in this channel. Check channel permissions and try again.",
                ephemeral=True,
            )
            return

        bot.status_autopost_channel_id = interaction.channel_id
        bot.status_autopost_guild_id = interaction.guild_id
        bot.status_autopost_mode = STATUS_SCHEDULE_MODE_WINDOWS
        bot.status_autopost_windows = windows
        bot._reset_status_autopost_deadline()
        if not bot.status_autopost.is_running():
            bot.status_autopost.start()
        bot._save_status_schedule_state()

        window_details = _format_window_details(windows)
        await interaction.followup.send(
            (
                f"Scheduled custom status windows in <#{interaction.channel_id}>.\n"
                f"{window_details}\n"
                "The bot posts only within configured windows. First scheduled post will be sent after the active interval."
            ),
            ephemeral=True,
        )

    @bot.tree.command(
        name="status_schedule_off",
        description="Disable periodic /status posts.",
        **command_kwargs,
    )
    async def status_schedule_off_command(interaction: discord.Interaction) -> None:
        await interaction.response.defer(ephemeral=True, thinking=False)

        if not bot._can_manage_schedule(interaction):
            await interaction.followup.send(
                "You need `Manage Server` permission to change scheduled status posts.",
                ephemeral=True,
            )
            return

        was_running = bot.status_autopost.is_running()
        if was_running:
            bot.status_autopost.cancel()
        bot.status_autopost_channel_id = None
        bot.status_autopost_guild_id = None
        bot.status_autopost_mode = STATUS_SCHEDULE_MODE_FIXED
        bot.status_autopost_windows = []
        bot.status_autopost_next_run_at = None
        bot.status_autopost_next_should_send = False
        bot._clear_status_schedule_state()

        if was_running:
            await interaction.followup.send("Scheduled status posts are now disabled.", ephemeral=True)
        else:
            await interaction.followup.send("Scheduled status posts were already disabled.", ephemeral=True)

    @bot.tree.command(
        name="status_schedule_show",
        description="Show scheduled /status posting settings.",
        **command_kwargs,
    )
    async def status_schedule_show_command(interaction: discord.Interaction) -> None:
        enabled = bot.status_autopost.is_running() and bot.status_autopost_channel_id is not None
        target = f"<#{bot.status_autopost_channel_id}>" if bot.status_autopost_channel_id else "not set"
        guild = str(bot.status_autopost_guild_id) if bot.status_autopost_guild_id else "not set"
        next_post = bot._format_status_next_post()
        mode = bot.status_autopost_mode
        if mode == STATUS_SCHEDULE_MODE_WINDOWS:
            display_lines = format_windows_for_display(bot.status_autopost_windows)
            if not display_lines:
                windows_text = "none"
            elif len(display_lines) > 8:
                shown = "\n".join(display_lines[:8])
                windows_text = f"{shown}\n...and {len(display_lines) - 8} more window(s)"
            else:
                windows_text = "\n".join(display_lines)
            schedule_details = (
                "Mode: `windows`\n"
                f"Windows:\n{windows_text}\n"
            )
        else:
            schedule_details = (
                "Mode: `fixed`\n"
                f"Interval: `{int(bot.status_autopost_interval_seconds // 60)}` minute(s)\n"
            )
        await interaction.response.send_message(
            (
                f"Enabled: `{enabled}`\n"
                f"{schedule_details}"
                f"Channel: {target}\n"
                f"Guild ID: `{guild}`\n"
                f"Next Post: `{next_post}`"
            ),
            ephemeral=True,
        )

    @bot.tree.command(name="health", description="Backend health and version from /api/health.", **command_kwargs)
    async def health_command(interaction: discord.Interaction) -> None:
        await bot._run_command(
            interaction=interaction,
            fetcher=bot.monitoring_client.fetch_health,
            formatter=format_health_embed,
        )

    @bot.tree.command(name="docker", description="Docker telemetry from /api/docker.", **command_kwargs)
    async def docker_command(interaction: discord.Interaction) -> None:
        await bot._run_command(
            interaction=interaction,
            fetcher=bot.monitoring_client.fetch_docker,
            formatter=format_docker_embed,
        )

    @bot.tree.command(name="gpu", description="GPU telemetry from /api/gpu.", **command_kwargs)
    async def gpu_command(interaction: discord.Interaction) -> None:
        await bot._run_command(
            interaction=interaction,
            fetcher=bot.monitoring_client.fetch_gpu,
            formatter=format_gpu_embed,
        )

    @bot.tree.command(name="system", description="Detailed system snapshot from /api/system.", **command_kwargs)
    async def system_command(interaction: discord.Interaction) -> None:
        await bot._run_command(
            interaction=interaction,
            fetcher=bot.monitoring_client.fetch_system,
            formatter=format_system_embed,
        )


def _format_window_details(windows: list[TimeWindowRule]) -> str:
    display_lines = format_windows_for_display(windows)
    if len(display_lines) > 8:
        shown = "\n".join(display_lines[:8])
        return f"{shown}\n...and {len(display_lines) - 8} more window(s)"
    return "\n".join(display_lines)
