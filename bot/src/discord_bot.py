from __future__ import annotations

import asyncio
import logging
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

import discord
from discord.ext import commands, tasks

from alert_state import AlertState
from bot_constants import (
    STATUS_AUTOPOST_RETRY_SECONDS,
    STATUS_AUTOPOST_TICK_SECONDS,
    STATUS_SCHEDULE_MAX_MINUTES,
    STATUS_SCHEDULE_MIN_MINUTES,
    STATUS_SCHEDULE_MODE_FIXED,
)
from commands import register_slash_commands
from config import BotConfig
from formatters import format_api_error_embed, format_status_embed
from mobile_push import MobilePushDispatcher
from monitoring_client import MonitoringAPIError, MonitoringClient
from schedule_policy import ScheduleMode, TimeWindowRule, compute_next_event
from services import (
    can_manage_schedule,
    resolve_alert_channel,
    resolve_channel,
    run_alert_polling,
    run_status_autopost,
    safe_send_embed,
)
from state import (
    clear_status_schedule_state,
    load_alert_state,
    load_status_schedule_state,
    save_alert_state,
    save_status_schedule_state,
)

logger = logging.getLogger("linux_monitoring.bot")


class MonitoringDiscordBot(commands.Bot):
    def __init__(self, config: BotConfig) -> None:
        super().__init__(command_prefix="!", intents=discord.Intents.none())
        self.config = config
        self.monitoring_client = MonitoringClient(
            base_url=config.monitor_api_base_url,
            timeout_seconds=config.request_timeout_seconds,
        )
        self.alert_state = AlertState(
            default_notify_after_seconds=config.alert_grace_seconds,
        )
        self.alert_state_path = Path(config.alert_state_file)
        self._load_alert_state()
        self.mobile_push_dispatcher = MobilePushDispatcher.from_config(config)
        self.guild_object = discord.Object(id=config.discord_guild_id) if config.discord_guild_id else None
        self.alert_polling.change_interval(seconds=float(config.poll_interval_seconds))
        self.status_autopost_mode: ScheduleMode = STATUS_SCHEDULE_MODE_FIXED
        self.status_autopost_interval_seconds = 3600
        self.status_autopost_windows: list[TimeWindowRule] = []
        self.status_autopost_channel_id: int | None = None
        self.status_autopost_guild_id: int | None = None
        self.status_autopost_next_run_at: datetime | None = None
        self.status_autopost_next_should_send = False
        self.status_autopost_state_path = Path(config.status_schedule_state_file)
        self._load_status_schedule_state()
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
        if self.status_autopost_channel_id is not None and not self.status_autopost.is_running():
            self.status_autopost.start()

    async def close(self) -> None:
        if self.alert_polling.is_running():
            self.alert_polling.cancel()
        if self.status_autopost.is_running():
            self.status_autopost.cancel()
        await self.monitoring_client.aclose()
        await super().close()

    def _register_commands(self) -> None:
        register_slash_commands(self)

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
            logger.warning("Command API request failed: %s", exc)
            embed = format_api_error_embed("Monitoring API request failed. Please try again shortly.")
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
                gpu_error = "GPU endpoint unavailable."
                logger.warning("Status GPU request failed: %s", gpu_result)
            else:
                gpu_payload = gpu_result
                gpu_error = None

            return format_status_embed(
                system=system_payload,
                gpu=gpu_payload,
                gpu_error=gpu_error,
            )
        except MonitoringAPIError as exc:
            logger.warning("Status request failed: %s", exc)
            return format_api_error_embed("Monitoring API request failed. Please try again shortly.")
        except Exception:
            logger.exception("Unexpected status command failure.")
            return format_api_error_embed("Unexpected error while building status.")

    @tasks.loop(seconds=60.0)
    async def alert_polling(self) -> None:
        await run_alert_polling(self)

    @tasks.loop(seconds=float(STATUS_AUTOPOST_TICK_SECONDS))
    async def status_autopost(self) -> None:
        await run_status_autopost(self)

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
        return await resolve_alert_channel(self)

    async def _resolve_channel(self, channel_id: int) -> discord.abc.Messageable | None:
        return await resolve_channel(self, channel_id)

    async def _safe_send_embed(
        self,
        *,
        channel: discord.abc.Messageable,
        embed: discord.Embed,
        context: str,
    ) -> bool:
        return await safe_send_embed(channel=channel, embed=embed, context=context)

    def _can_manage_schedule(self, interaction: discord.Interaction) -> bool:
        return can_manage_schedule(interaction)

    def _load_status_schedule_state(self) -> None:
        schedule_state = load_status_schedule_state(
            path=self.status_autopost_state_path,
            configured_guild_id=self.config.discord_guild_id,
            min_interval_seconds=STATUS_SCHEDULE_MIN_MINUTES * 60,
            max_interval_seconds=STATUS_SCHEDULE_MAX_MINUTES * 60,
        )
        if schedule_state is None:
            return

        self.status_autopost_channel_id = schedule_state.channel_id
        self.status_autopost_guild_id = schedule_state.guild_id
        self.status_autopost_mode = schedule_state.mode
        self.status_autopost_interval_seconds = schedule_state.interval_seconds
        self.status_autopost_windows = schedule_state.windows
        self._reset_status_autopost_deadline()
        logger.info(
            "Loaded status schedule: mode=%s guild_id=%s channel_id=%s windows=%s",
            self.status_autopost_mode,
            self.status_autopost_guild_id,
            self.status_autopost_channel_id,
            len(self.status_autopost_windows),
        )

    def _save_status_schedule_state(self) -> None:
        save_status_schedule_state(
            path=self.status_autopost_state_path,
            mode=self.status_autopost_mode,
            guild_id=self.status_autopost_guild_id,
            channel_id=self.status_autopost_channel_id,
            interval_seconds=self.status_autopost_interval_seconds,
            windows=self.status_autopost_windows,
        )

    def _clear_status_schedule_state(self) -> None:
        clear_status_schedule_state(self.status_autopost_state_path)

    def _reset_status_autopost_deadline(self) -> None:
        next_event = compute_next_event(
            mode=self.status_autopost_mode,
            now_utc=datetime.now(timezone.utc),
            fixed_interval_seconds=self.status_autopost_interval_seconds,
            windows=self.status_autopost_windows,
        )
        if next_event is None:
            self.status_autopost_next_run_at = None
            self.status_autopost_next_should_send = False
            return
        self.status_autopost_next_run_at = next_event.run_at_utc
        self.status_autopost_next_should_send = next_event.should_send

    def _schedule_status_autopost_retry(self) -> None:
        self.status_autopost_next_run_at = datetime.now(timezone.utc) + timedelta(seconds=STATUS_AUTOPOST_RETRY_SECONDS)
        self.status_autopost_next_should_send = True

    def _is_status_autopost_due(self) -> bool:
        if self.status_autopost_next_run_at is None:
            self._reset_status_autopost_deadline()
            return False
        now = datetime.now(timezone.utc)
        # Allow a tiny boundary tolerance to avoid skipping a full interval on clock jitter.
        return now + timedelta(seconds=1) >= self.status_autopost_next_run_at

    def _format_status_next_post(self) -> str:
        if self.status_autopost_channel_id is None or self.status_autopost_next_run_at is None:
            return "not scheduled"
        remaining = int((self.status_autopost_next_run_at - datetime.now(timezone.utc)).total_seconds())
        if remaining <= 0:
            return "due now"
        prefix = "in"
        if not self.status_autopost_next_should_send:
            prefix = "window switch in"
        return f"{prefix} ~{(remaining + 59) // 60} minute(s)"

    def _load_alert_state(self) -> None:
        load_alert_state(self.alert_state_path, self.alert_state)

    def _save_alert_state(self) -> None:
        save_alert_state(self.alert_state_path, self.alert_state)
