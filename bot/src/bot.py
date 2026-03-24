from __future__ import annotations

import asyncio
import logging
from typing import Any

import discord
from discord import app_commands
from discord.ext import commands, tasks

from alert_rules import evaluate_alerts
from alert_state import AlertState
from config import BotConfig
from formatters import (
    format_alert_embed,
    format_api_error_embed,
    format_docker_embed,
    format_gpu_embed,
    format_health_embed,
    format_recovery_embed,
    format_status_embed,
    format_system_embed,
)
from monitoring_client import MonitoringAPIError, MonitoringClient

logger = logging.getLogger("linux_monitoring.bot")


class MonitoringDiscordBot(commands.Bot):
    def __init__(self, config: BotConfig) -> None:
        super().__init__(command_prefix="!", intents=discord.Intents.none())
        self.config = config
        self.monitoring_client = MonitoringClient(
            base_url=config.monitor_api_base_url,
            timeout_seconds=config.request_timeout_seconds,
        )
        self.alert_state = AlertState()
        self.guild_object = discord.Object(id=config.discord_guild_id) if config.discord_guild_id else None
        self.alert_polling.change_interval(seconds=float(config.poll_interval_seconds))
        self.status_autopost_interval_seconds = 3600
        self.status_autopost_channel_id: int | None = None
        self._register_commands()

    async def setup_hook(self) -> None:
        if self.guild_object is None:
            await self.tree.sync()
            logger.info("Synced global slash commands.")
        else:
            await self.tree.sync(guild=self.guild_object)
            logger.info("Synced guild slash commands for guild_id=%s.", self.guild_object.id)

        if not self.alert_polling.is_running():
            self.alert_polling.start()

    async def close(self) -> None:
        if self.alert_polling.is_running():
            self.alert_polling.cancel()
        if self.status_autopost.is_running():
            self.status_autopost.cancel()
        await self.monitoring_client.aclose()
        await super().close()

    def _register_commands(self) -> None:
        command_kwargs: dict[str, Any] = {}
        if self.guild_object is not None:
            command_kwargs["guild"] = self.guild_object

        @self.tree.command(name="status", description="Detailed live status (CPU/GPU/RAM/storage/temps/uptime).", **command_kwargs)
        async def status_command(interaction: discord.Interaction) -> None:
            await interaction.response.defer(thinking=True)
            embed = await self._build_status_embed()
            await interaction.followup.send(embed=embed)

        @self.tree.command(
            name="status_schedule",
            description="Enable periodic /status posts in this channel.",
            **command_kwargs,
        )
        @app_commands.describe(interval_minutes="How often to post status updates.")
        async def status_schedule_command(
            interaction: discord.Interaction,
            interval_minutes: app_commands.Range[int, 5, 1440],
        ) -> None:
            await interaction.response.defer(ephemeral=True, thinking=False)

            if not self._can_manage_schedule(interaction):
                await interaction.followup.send(
                    "You need `Manage Server` permission to change scheduled status posts.",
                    ephemeral=True,
                )
                return

            if interaction.channel_id is None:
                await interaction.followup.send("This command must be used in a server channel.", ephemeral=True)
                return

            channel = await self._resolve_channel(interaction.channel_id)
            if channel is None:
                await interaction.followup.send("I cannot access this channel.", ephemeral=True)
                return

            self.status_autopost_channel_id = interaction.channel_id
            self.status_autopost_interval_seconds = int(interval_minutes) * 60
            self.status_autopost.change_interval(seconds=float(self.status_autopost_interval_seconds))
            if not self.status_autopost.is_running():
                self.status_autopost.start()

            embed = await self._build_status_embed()
            await channel.send(embed=embed)
            await interaction.followup.send(
                (
                    f"Scheduled status posts every `{interval_minutes}` minute(s) "
                    f"in <#{interaction.channel_id}>."
                ),
                ephemeral=True,
            )

        @self.tree.command(
            name="status_schedule_off",
            description="Disable periodic /status posts.",
            **command_kwargs,
        )
        async def status_schedule_off_command(interaction: discord.Interaction) -> None:
            await interaction.response.defer(ephemeral=True, thinking=False)

            if not self._can_manage_schedule(interaction):
                await interaction.followup.send(
                    "You need `Manage Server` permission to change scheduled status posts.",
                    ephemeral=True,
                )
                return

            was_running = self.status_autopost.is_running()
            if was_running:
                self.status_autopost.cancel()
            self.status_autopost_channel_id = None

            if was_running:
                await interaction.followup.send("Scheduled status posts are now disabled.", ephemeral=True)
            else:
                await interaction.followup.send("Scheduled status posts were already disabled.", ephemeral=True)

        @self.tree.command(
            name="status_schedule_show",
            description="Show scheduled /status posting settings.",
            **command_kwargs,
        )
        async def status_schedule_show_command(interaction: discord.Interaction) -> None:
            interval_minutes = int(self.status_autopost_interval_seconds // 60)
            enabled = self.status_autopost.is_running() and self.status_autopost_channel_id is not None
            target = f"<#{self.status_autopost_channel_id}>" if self.status_autopost_channel_id else "not set"
            await interaction.response.send_message(
                (
                    f"Enabled: `{enabled}`\n"
                    f"Interval: `{interval_minutes}` minute(s)\n"
                    f"Channel: {target}"
                ),
                ephemeral=True,
            )

        @self.tree.command(name="health", description="Backend health and version from /api/health.", **command_kwargs)
        async def health_command(interaction: discord.Interaction) -> None:
            await self._run_command(
                interaction=interaction,
                fetcher=self.monitoring_client.fetch_health,
                formatter=format_health_embed,
            )

        @self.tree.command(name="docker", description="Docker telemetry from /api/docker.", **command_kwargs)
        async def docker_command(interaction: discord.Interaction) -> None:
            await self._run_command(
                interaction=interaction,
                fetcher=self.monitoring_client.fetch_docker,
                formatter=format_docker_embed,
            )

        @self.tree.command(name="gpu", description="GPU telemetry from /api/gpu.", **command_kwargs)
        async def gpu_command(interaction: discord.Interaction) -> None:
            await self._run_command(
                interaction=interaction,
                fetcher=self.monitoring_client.fetch_gpu,
                formatter=format_gpu_embed,
            )

        @self.tree.command(name="system", description="Detailed system snapshot from /api/system.", **command_kwargs)
        async def system_command(interaction: discord.Interaction) -> None:
            await self._run_command(
                interaction=interaction,
                fetcher=self.monitoring_client.fetch_system,
                formatter=format_system_embed,
            )

    async def _run_command(
        self,
        *,
        interaction: discord.Interaction,
        fetcher: Any,
        formatter: Any,
    ) -> None:
        await interaction.response.defer(thinking=True)
        try:
            payload = await fetcher()
            embed = formatter(payload)
        except MonitoringAPIError as exc:
            embed = format_api_error_embed(str(exc))
        await interaction.followup.send(embed=embed)

    async def _build_status_embed(self) -> discord.Embed:
        try:
            system_result, gpu_result = await asyncio.gather(
                self.monitoring_client.fetch_system(),
                self.monitoring_client.fetch_gpu(),
                return_exceptions=True,
            )

            if isinstance(system_result, Exception):
                raise system_result

            system_payload = system_result
            gpu_payload: dict[str, Any] | None
            gpu_error: str | None

            if isinstance(gpu_result, Exception):
                gpu_payload = None
                gpu_error = str(gpu_result)
            else:
                gpu_payload = gpu_result
                gpu_error = None

            return format_status_embed(
                system=system_payload,
                gpu=gpu_payload,
                gpu_error=gpu_error,
            )
        except MonitoringAPIError as exc:
            return format_api_error_embed(str(exc))
        except Exception as exc:
            return format_api_error_embed(str(exc))

    @tasks.loop(seconds=60.0)
    async def alert_polling(self) -> None:
        channel = await self._resolve_alert_channel()
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
            health_payload = await self.monitoring_client.fetch_health()
        except MonitoringAPIError as exc:
            backend_error = str(exc)

        if backend_error is None:
            endpoints = {
                "summary": self.monitoring_client.fetch_summary(),
                "system": self.monitoring_client.fetch_system(),
                "gpu": self.monitoring_client.fetch_gpu(),
                "docker": self.monitoring_client.fetch_docker(),
            }
            results = await asyncio.gather(*endpoints.values(), return_exceptions=True)
            for endpoint_name, result in zip(endpoints.keys(), results):
                if isinstance(result, Exception):
                    endpoint_errors[endpoint_name] = str(result)
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
            config=self.config,
            health=health_payload,
            summary=summary_payload,
            system=system_payload,
            gpu=gpu_payload,
            docker=docker_payload,
            backend_error=backend_error,
            endpoint_errors=endpoint_errors,
        )

        new_alerts, recoveries = self.alert_state.transition(active_alerts)
        if not new_alerts and not recoveries:
            return

        for alert in new_alerts:
            await channel.send(embed=format_alert_embed(alert))
        for recovery in recoveries:
            await channel.send(embed=format_recovery_embed(recovery))

    @tasks.loop(seconds=3600.0)
    async def status_autopost(self) -> None:
        if self.status_autopost_channel_id is None:
            return

        channel = await self._resolve_channel(self.status_autopost_channel_id)
        if channel is None:
            return

        embed = await self._build_status_embed()
        await channel.send(embed=embed)

    @alert_polling.before_loop
    async def _before_alert_polling(self) -> None:
        await self.wait_until_ready()

    @status_autopost.before_loop
    async def _before_status_autopost(self) -> None:
        await self.wait_until_ready()

    @alert_polling.error
    async def _handle_alert_polling_error(self, exc: Exception) -> None:
        logger.exception("Alert polling loop crashed: %s", exc)

    @status_autopost.error
    async def _handle_status_autopost_error(self, exc: Exception) -> None:
        logger.exception("Status autopost loop crashed: %s", exc)

    async def _resolve_alert_channel(self) -> discord.abc.Messageable | None:
        return await self._resolve_channel(self.config.discord_channel_id)

    async def _resolve_channel(self, channel_id: int) -> discord.abc.Messageable | None:
        channel = self.get_channel(channel_id)
        if channel is None:
            try:
                channel = await self.fetch_channel(channel_id)
            except discord.HTTPException as exc:
                logger.warning("Could not fetch channel %s: %s", channel_id, exc)
                return None

        if not hasattr(channel, "send"):
            logger.warning("Configured channel %s is not send-capable.", channel_id)
            return None
        return channel

    def _can_manage_schedule(self, interaction: discord.Interaction) -> bool:
        guild = interaction.guild
        if guild is None:
            return False

        user = interaction.user
        if user.id == guild.owner_id:
            return True

        interaction_permissions = getattr(interaction, "permissions", None)
        if isinstance(interaction_permissions, discord.Permissions):
            if interaction_permissions.administrator or interaction_permissions.manage_guild:
                return True

        member_permissions = getattr(user, "guild_permissions", None)
        if isinstance(member_permissions, discord.Permissions):
            if member_permissions.administrator or member_permissions.manage_guild:
                return True

        return False


def configure_logging() -> None:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )


def main() -> None:
    configure_logging()
    try:
        config = BotConfig.from_env()
    except ValueError as exc:
        raise SystemExit(f"Configuration error: {exc}") from exc

    bot = MonitoringDiscordBot(config)
    bot.run(config.discord_bot_token)


if __name__ == "__main__":
    main()
