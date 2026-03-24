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
            "ENABLE_DOCKER_ALERTS": "false",
            "ENABLE_RAID_ALERTS": "true",
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
        self.assertFalse(config.enable_docker_alerts)
        self.assertTrue(config.enable_raid_alerts)

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


if __name__ == "__main__":
    unittest.main()
