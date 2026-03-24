from __future__ import annotations

import asyncio
import json
import logging
from datetime import datetime, timedelta, timezone
from pathlib import Path
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
from schedule_policy import (
    ScheduleMode,
    TimeWindowRule,
    compute_next_event,
    format_windows_for_display,
    parse_windows_payload,
    parse_windows_spec,
    serialize_windows_payload,
)

logger = logging.getLogger("linux_monitoring.bot")
STATUS_SCHEDULE_MIN_MINUTES = 5
STATUS_SCHEDULE_MAX_MINUTES = 1440
STATUS_SCHEDULE_MAX_WINDOWS = 24
STATUS_AUTOPOST_TICK_SECONDS = 30
STATUS_AUTOPOST_RETRY_SECONDS = 60
STATUS_SCHEDULE_MODE_FIXED: ScheduleMode = "fixed"
STATUS_SCHEDULE_MODE_WINDOWS: ScheduleMode = "windows"


class MonitoringDiscordBot(commands.Bot):
    def __init__(self, config: BotConfig) -> None:
        super().__init__(command_prefix="!", intents=discord.Intents.none())
        self.config = config
        self.monitoring_client = MonitoringClient(
            base_url=config.monitor_api_base_url,
            timeout_seconds=config.request_timeout_seconds,
        )
        self.alert_state = AlertState()
        self.alert_state_path = Path(config.alert_state_file)
        self._load_alert_state()
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
            interval_minutes: app_commands.Range[int, STATUS_SCHEDULE_MIN_MINUTES, STATUS_SCHEDULE_MAX_MINUTES],
        ) -> None:
            await interaction.response.defer(ephemeral=True, thinking=False)

            if not self._can_manage_schedule(interaction):
                await interaction.followup.send(
                    "You need `Manage Server` permission to change scheduled status posts.",
                    ephemeral=True,
                )
                return

            if interaction.guild_id is None:
                await interaction.followup.send("This command must be used in a server.", ephemeral=True)
                return
            if self.config.discord_guild_id is not None and interaction.guild_id != self.config.discord_guild_id:
                await interaction.followup.send(
                    "This bot is configured for a different server. Check `DISCORD_GUILD_ID`.",
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

            embed = await self._build_status_embed()
            sent = await self._safe_send_embed(
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

            self.status_autopost_channel_id = interaction.channel_id
            self.status_autopost_guild_id = interaction.guild_id
            self.status_autopost_mode = STATUS_SCHEDULE_MODE_FIXED
            self.status_autopost_windows = []
            self.status_autopost_interval_seconds = int(interval_minutes) * 60
            self._reset_status_autopost_deadline()
            if not self.status_autopost.is_running():
                self.status_autopost.start()
            self._save_status_schedule_state()

            await interaction.followup.send(
                (
                    f"Scheduled status posts every `{interval_minutes}` minute(s) "
                    f"in <#{interaction.channel_id}>. First scheduled post will be sent after the interval."
                ),
                ephemeral=True,
            )

        @self.tree.command(
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

            if not self._can_manage_schedule(interaction):
                await interaction.followup.send(
                    "You need `Manage Server` permission to change scheduled status posts.",
                    ephemeral=True,
                )
                return

            if interaction.guild_id is None:
                await interaction.followup.send("This command must be used in a server.", ephemeral=True)
                return
            if self.config.discord_guild_id is not None and interaction.guild_id != self.config.discord_guild_id:
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

            channel = await self._resolve_channel(interaction.channel_id)
            if channel is None:
                await interaction.followup.send("I cannot access this channel.", ephemeral=True)
                return

            embed = await self._build_status_embed()
            sent = await self._safe_send_embed(
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

            self.status_autopost_channel_id = interaction.channel_id
            self.status_autopost_guild_id = interaction.guild_id
            self.status_autopost_mode = STATUS_SCHEDULE_MODE_WINDOWS
            self.status_autopost_windows = windows
            self._reset_status_autopost_deadline()
            if not self.status_autopost.is_running():
                self.status_autopost.start()
            self._save_status_schedule_state()

            display_lines = format_windows_for_display(windows)
            if len(display_lines) > 8:
                shown = "\n".join(display_lines[:8])
                window_details = f"{shown}\n...and {len(display_lines) - 8} more window(s)"
            else:
                window_details = "\n".join(display_lines)
            await interaction.followup.send(
                (
                    f"Scheduled custom status windows in <#{interaction.channel_id}>.\n"
                    f"{window_details}\n"
                    "The bot posts only within configured windows. First scheduled post will be sent after the active interval."
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
            self.status_autopost_guild_id = None
            self.status_autopost_mode = STATUS_SCHEDULE_MODE_FIXED
            self.status_autopost_windows = []
            self.status_autopost_next_run_at = None
            self.status_autopost_next_should_send = False
            self._clear_status_schedule_state()

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
            enabled = self.status_autopost.is_running() and self.status_autopost_channel_id is not None
            target = f"<#{self.status_autopost_channel_id}>" if self.status_autopost_channel_id else "not set"
            guild = str(self.status_autopost_guild_id) if self.status_autopost_guild_id else "not set"
            next_post = self._format_status_next_post()
            mode = self.status_autopost_mode
            if mode == STATUS_SCHEDULE_MODE_WINDOWS:
                display_lines = format_windows_for_display(self.status_autopost_windows)
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
                    f"Interval: `{int(self.status_autopost_interval_seconds // 60)}` minute(s)\n"
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
        except Exception as exc:
            logger.exception("Unexpected status command failure.")
            return format_api_error_embed("Unexpected error while building status.")

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
            logger.warning("Health polling failed: %s", exc)
            backend_error = "health endpoint is unavailable."

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
        self._save_alert_state()

        for alert in new_alerts:
            await self._safe_send_embed(
                channel=channel,
                embed=format_alert_embed(alert),
                context=f"alert:{alert.key}",
            )
        for recovery in recoveries:
            await self._safe_send_embed(
                channel=channel,
                embed=format_recovery_embed(recovery),
                context=f"recovery:{recovery.key}",
            )

    @tasks.loop(seconds=float(STATUS_AUTOPOST_TICK_SECONDS))
    async def status_autopost(self) -> None:
        if self.status_autopost_channel_id is None:
            return
        if not self._is_status_autopost_due():
            return
        if not self.status_autopost_next_should_send:
            self._reset_status_autopost_deadline()
            return

        channel = await self._resolve_channel(self.status_autopost_channel_id)
        if channel is None:
            self._schedule_status_autopost_retry()
            return
        channel_guild = getattr(channel, "guild", None)
        channel_guild_id = getattr(channel_guild, "id", None)
        if self.status_autopost_guild_id is not None and channel_guild_id != self.status_autopost_guild_id:
            logger.warning(
                "Skipping status autopost due to guild mismatch: expected=%s actual=%s",
                self.status_autopost_guild_id,
                channel_guild_id,
            )
            self._schedule_status_autopost_retry()
            return

        embed = await self._build_status_embed()
        sent = await self._safe_send_embed(channel=channel, embed=embed, context="status_autopost")
        if sent:
            self._reset_status_autopost_deadline()
            logger.info(
                "Posted scheduled status to channel_id=%s; next run at %s",
                self.status_autopost_channel_id,
                self.status_autopost_next_run_at.isoformat() if self.status_autopost_next_run_at else "unknown",
            )
        else:
            self._schedule_status_autopost_retry()

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

    async def _safe_send_embed(
        self,
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

    def _load_status_schedule_state(self) -> None:
        if not self.status_autopost_state_path.exists():
            return

        try:
            raw_text = self.status_autopost_state_path.read_text(encoding="utf-8")
            payload = json.loads(raw_text)
        except (OSError, json.JSONDecodeError) as exc:
            logger.warning("Could not read status schedule state from %s: %s", self.status_autopost_state_path, exc)
            return

        if not isinstance(payload, dict):
            logger.warning("Status schedule state file is not an object: %s", self.status_autopost_state_path)
            return

        channel_id_value = payload.get("channel_id")
        guild_id_value = payload.get("guild_id")
        mode_value = str(payload.get("mode") or STATUS_SCHEDULE_MODE_FIXED).strip().lower()
        mode: ScheduleMode
        if mode_value == STATUS_SCHEDULE_MODE_WINDOWS:
            mode = STATUS_SCHEDULE_MODE_WINDOWS
        elif mode_value == STATUS_SCHEDULE_MODE_FIXED:
            mode = STATUS_SCHEDULE_MODE_FIXED
        else:
            logger.warning("Unknown status schedule mode in state file: %s", mode_value)
            return

        channel_id = _safe_positive_int(channel_id_value)
        guild_id = _safe_positive_int(guild_id_value)
        if guild_id is None:
            guild_id = self.config.discord_guild_id

        min_interval = STATUS_SCHEDULE_MIN_MINUTES * 60
        max_interval = STATUS_SCHEDULE_MAX_MINUTES * 60
        guild_valid = guild_id is not None
        if self.config.discord_guild_id is not None:
            guild_valid = guild_id == self.config.discord_guild_id

        if channel_id is None or not guild_valid:
            logger.warning("Status schedule state has invalid values and will be ignored.")
            return

        if mode == STATUS_SCHEDULE_MODE_FIXED:
            interval_seconds_value = payload.get("interval_seconds")
            interval_seconds = _safe_positive_int(interval_seconds_value)
            interval_valid = interval_seconds is not None and min_interval <= interval_seconds <= max_interval
            if not interval_valid:
                logger.warning("Invalid fixed schedule interval in state file.")
                return

            self.status_autopost_interval_seconds = interval_seconds
            self.status_autopost_windows = []
        else:
            raw_windows = payload.get("windows")
            try:
                parsed_windows = parse_windows_payload(
                    raw_windows,
                    min_interval_seconds=min_interval,
                    max_interval_seconds=max_interval,
                )
            except ValueError as exc:
                logger.warning("Invalid windows schedule in state file: %s", exc)
                return
            if not parsed_windows:
                logger.warning("Windows schedule state is empty.")
                return
            self.status_autopost_windows = parsed_windows

        self.status_autopost_channel_id = channel_id
        self.status_autopost_guild_id = guild_id
        self.status_autopost_mode = mode
        self._reset_status_autopost_deadline()
        logger.info(
            "Loaded status schedule: mode=%s guild_id=%s channel_id=%s windows=%s",
            self.status_autopost_mode,
            self.status_autopost_guild_id,
            self.status_autopost_channel_id,
            len(self.status_autopost_windows),
        )

    def _save_status_schedule_state(self) -> None:
        if self.status_autopost_channel_id is None or self.status_autopost_guild_id is None:
            return

        payload = {
            "mode": self.status_autopost_mode,
            "guild_id": self.status_autopost_guild_id,
            "channel_id": self.status_autopost_channel_id,
            "interval_seconds": self.status_autopost_interval_seconds,
            "windows": serialize_windows_payload(self.status_autopost_windows),
        }
        serialized = json.dumps(payload, separators=(",", ":"), sort_keys=True)

        try:
            self.status_autopost_state_path.parent.mkdir(parents=True, exist_ok=True)
            tmp_path = self.status_autopost_state_path.with_name(self.status_autopost_state_path.name + ".tmp")
            tmp_path.write_text(serialized, encoding="utf-8")
            tmp_path.replace(self.status_autopost_state_path)
        except OSError as exc:
            logger.warning("Could not persist status schedule state to %s: %s", self.status_autopost_state_path, exc)

    def _clear_status_schedule_state(self) -> None:
        try:
            if self.status_autopost_state_path.exists():
                self.status_autopost_state_path.unlink()
        except OSError as exc:
            logger.warning("Could not clear status schedule state at %s: %s", self.status_autopost_state_path, exc)

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
        self.status_autopost_next_run_at = datetime.now(timezone.utc) + timedelta(
            seconds=STATUS_AUTOPOST_RETRY_SECONDS
        )
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
        if not self.alert_state_path.exists():
            return

        try:
            raw_text = self.alert_state_path.read_text(encoding="utf-8")
            payload = json.loads(raw_text)
        except (OSError, json.JSONDecodeError) as exc:
            logger.warning("Could not read alert state from %s: %s", self.alert_state_path, exc)
            return

        if not isinstance(payload, dict):
            logger.warning("Alert state file is not an object: %s", self.alert_state_path)
            return

        self.alert_state.load_snapshot(payload)
        logger.info("Loaded alert state with %s active alert(s).", self.alert_state.active_count)

    def _save_alert_state(self) -> None:
        if self.alert_state.active_count == 0:
            try:
                if self.alert_state_path.exists():
                    self.alert_state_path.unlink()
            except OSError as exc:
                logger.warning("Could not clear alert state at %s: %s", self.alert_state_path, exc)
            return

        payload = self.alert_state.to_snapshot()
        serialized = json.dumps(payload, separators=(",", ":"), sort_keys=True)

        try:
            self.alert_state_path.parent.mkdir(parents=True, exist_ok=True)
            tmp_path = self.alert_state_path.with_name(self.alert_state_path.name + ".tmp")
            tmp_path.write_text(serialized, encoding="utf-8")
            tmp_path.replace(self.alert_state_path)
        except OSError as exc:
            logger.warning("Could not persist alert state to %s: %s", self.alert_state_path, exc)


def _safe_positive_int(value: object) -> int | None:
    try:
        parsed = int(value)  # type: ignore[arg-type]
    except (TypeError, ValueError):
        return None
    if parsed <= 0:
        return None
    return parsed


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
