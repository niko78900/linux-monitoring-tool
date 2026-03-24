from __future__ import annotations

import asyncio
import logging
from typing import Any

import discord
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
        await self.monitoring_client.aclose()
        await super().close()

    def _register_commands(self) -> None:
        command_kwargs: dict[str, Any] = {}
        if self.guild_object is not None:
            command_kwargs["guild"] = self.guild_object

        @self.tree.command(name="status", description="Quick system status from /api/summary.", **command_kwargs)
        async def status_command(interaction: discord.Interaction) -> None:
            await self._run_command(
                interaction=interaction,
                fetcher=self.monitoring_client.fetch_summary,
                formatter=format_status_embed,
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

    @alert_polling.before_loop
    async def _before_alert_polling(self) -> None:
        await self.wait_until_ready()

    @alert_polling.error
    async def _handle_alert_polling_error(self, exc: Exception) -> None:
        logger.exception("Alert polling loop crashed: %s", exc)

    async def _resolve_alert_channel(self) -> discord.abc.Messageable | None:
        channel = self.get_channel(self.config.discord_channel_id)
        if channel is None:
            try:
                channel = await self.fetch_channel(self.config.discord_channel_id)
            except discord.HTTPException as exc:
                logger.warning("Could not fetch alert channel %s: %s", self.config.discord_channel_id, exc)
                return None

        if not hasattr(channel, "send"):
            logger.warning("Configured channel %s is not send-capable.", self.config.discord_channel_id)
            return None
        return channel


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
