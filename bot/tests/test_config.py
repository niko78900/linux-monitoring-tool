from __future__ import annotations

import sys
import unittest
from pathlib import Path

SRC_DIR = Path(__file__).resolve().parents[1] / "src"
if str(SRC_DIR) not in sys.path:
    sys.path.insert(0, str(SRC_DIR))

from config import BotConfig  # noqa: E402


class BotConfigTests(unittest.TestCase):
    def test_from_env_parses_required_and_optional_values(self) -> None:
        env = {
            "DISCORD_BOT_TOKEN": "secret-token",
            "DISCORD_GUILD_ID": "1234567890",
            "DISCORD_CHANNEL_ID": "987654321",
            "MONITOR_API_BASE_URL": "http://127.0.0.1:4040/",
            "POLL_INTERVAL_SECONDS": "45",
            "CPU_ALERT_THRESHOLD": "88",
            "MEMORY_ALERT_THRESHOLD": "91.5",
            "DISK_ALERT_THRESHOLD": "92",
            "GPU_TEMP_ALERT_THRESHOLD": "82",
            "GPU_USAGE_ALERT_THRESHOLD": "87",
            "ENABLE_DOCKER_ALERTS": "false",
            "ENABLE_RAID_ALERTS": "true",
            "MOBILE_PUSH_ENABLED": "true",
            "MOBILE_PUSH_INCLUDE_RECOVERY": "false",
            "MOBILE_PUSH_TOKEN_REGISTRY_FILE": "/tmp/mobile_push_tokens.json",
            "FIREBASE_SERVICE_ACCOUNT_FILE": "/tmp/firebase.json",
        }

        config = BotConfig.from_env(env)

        self.assertEqual(config.discord_bot_token, "secret-token")
        self.assertEqual(config.discord_guild_id, 1234567890)
        self.assertEqual(config.discord_channel_id, 987654321)
        self.assertEqual(config.monitor_api_base_url, "http://127.0.0.1:4040")
        self.assertEqual(config.poll_interval_seconds, 45)
        self.assertEqual(config.cpu_alert_threshold, 88.0)
        self.assertEqual(config.memory_alert_threshold, 91.5)
        self.assertEqual(config.disk_alert_threshold, 92.0)
        self.assertEqual(config.gpu_temp_alert_threshold, 82.0)
        self.assertEqual(config.gpu_usage_alert_threshold, 87.0)
        self.assertEqual(config.alert_grace_seconds, 300)
        self.assertFalse(config.enable_docker_alerts)
        self.assertTrue(config.enable_raid_alerts)
        self.assertTrue(config.mobile_push_enabled)
        self.assertFalse(config.mobile_push_include_recovery)
        self.assertEqual(
            Path(config.mobile_push_token_registry_file),
            Path("/tmp/mobile_push_tokens.json").expanduser(),
        )
        self.assertEqual(
            Path(config.firebase_service_account_file),
            Path("/tmp/firebase.json").expanduser(),
        )
        self.assertTrue(config.status_schedule_state_file.endswith("status_schedule_state.json"))
        self.assertTrue(config.alert_state_file.endswith("alert_state.json"))

    def test_from_env_allows_empty_optional_guild_id(self) -> None:
        env = {
            "DISCORD_BOT_TOKEN": "secret-token",
            "DISCORD_GUILD_ID": "",
            "DISCORD_CHANNEL_ID": "111111",
            "MONITOR_API_BASE_URL": "http://monitor:4040",
        }
        config = BotConfig.from_env(env)
        self.assertIsNone(config.discord_guild_id)

    def test_from_env_rejects_invalid_threshold(self) -> None:
        env = {
            "DISCORD_BOT_TOKEN": "secret-token",
            "DISCORD_CHANNEL_ID": "111111",
            "MONITOR_API_BASE_URL": "http://monitor:4040",
            "CPU_ALERT_THRESHOLD": "120",
        }
        with self.assertRaises(ValueError):
            BotConfig.from_env(env)

    def test_from_env_resolves_relative_schedule_state_file(self) -> None:
        env = {
            "DISCORD_BOT_TOKEN": "secret-token",
            "DISCORD_CHANNEL_ID": "111111",
            "MONITOR_API_BASE_URL": "http://monitor:4040",
            "STATUS_SCHEDULE_STATE_FILE": "state/schedule.json",
            "ALERT_GRACE_SECONDS": "120",
        }

        config = BotConfig.from_env(env)
        self.assertTrue(Path(config.status_schedule_state_file).is_absolute())
        self.assertTrue(config.status_schedule_state_file.endswith(str(Path("state") / "schedule.json")))
        self.assertEqual(config.alert_grace_seconds, 120)

    def test_from_env_supports_legacy_endpoint_alert_grace_seconds(self) -> None:
        env = {
            "DISCORD_BOT_TOKEN": "secret-token",
            "DISCORD_CHANNEL_ID": "111111",
            "MONITOR_API_BASE_URL": "http://monitor:4040",
            "ENDPOINT_ALERT_GRACE_SECONDS": "180",
        }

        config = BotConfig.from_env(env)
        self.assertEqual(config.alert_grace_seconds, 180)

    def test_from_env_resolves_relative_alert_state_file(self) -> None:
        env = {
            "DISCORD_BOT_TOKEN": "secret-token",
            "DISCORD_CHANNEL_ID": "111111",
            "MONITOR_API_BASE_URL": "http://monitor:4040",
            "ALERT_STATE_FILE": "state/alerts.json",
        }

        config = BotConfig.from_env(env)
        self.assertTrue(Path(config.alert_state_file).is_absolute())
        self.assertTrue(config.alert_state_file.endswith(str(Path("state") / "alerts.json")))


if __name__ == "__main__":
    unittest.main()
