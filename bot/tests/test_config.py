from __future__ import annotations

import sys
import unittest
from pathlib import Path

SRC_DIR = Path(__file__).resolve().parents[1] / "src"
if str(SRC_DIR) not in sys.path:
    sys.path.insert(0, str(SRC_DIR))

from config import BotConfig  # noqa: E402


class BotConfigTests(unittest.TestCase):
    def test_from_env_parses_event_consumer_settings(self) -> None:
        env = {
            "DISCORD_BOT_TOKEN": "secret-token",
            "DISCORD_GUILD_ID": "1234567890",
            "DISCORD_CHANNEL_ID": "987654321",
            "MONITORING_API_BASE_URL": "http://127.0.0.1:4040/api",
            "POLL_INTERVAL_SECONDS": "45",
            "ALERT_CONSUMER_API_TOKEN": "consumer-token",
            "DISCORD_ALERT_CURSOR_FILE": "/tmp/discord_alert_cursor.json",
            "DISCORD_ALERT_REPLAY_ON_FIRST_START": "true",
        }

        config = BotConfig.from_env(env)

        self.assertEqual(config.discord_bot_token, "secret-token")
        self.assertEqual(config.discord_guild_id, 1234567890)
        self.assertEqual(config.discord_channel_id, 987654321)
        self.assertEqual(config.monitor_api_base_url, "http://127.0.0.1:4040/api")
        self.assertEqual(config.poll_interval_seconds, 45)
        self.assertEqual(config.alert_consumer_api_token, "consumer-token")
        self.assertTrue(config.discord_alert_cursor_file.endswith("discord_alert_cursor.json"))
        self.assertTrue(config.discord_alert_replay_on_first_start)
        self.assertTrue(config.status_schedule_state_file.endswith("status_schedule_state.json"))

    def test_from_env_accepts_legacy_monitor_url_and_appends_api_prefix(self) -> None:
        env = {
            "DISCORD_BOT_TOKEN": "secret-token",
            "DISCORD_CHANNEL_ID": "111111",
            "MONITOR_API_BASE_URL": "http://monitor:4040",
            "ALERT_CONSUMER_API_TOKEN": "consumer-token",
        }

        config = BotConfig.from_env(env)

        self.assertEqual(config.monitor_api_base_url, "http://monitor:4040/api")

    def test_from_env_requires_consumer_token(self) -> None:
        env = {
            "DISCORD_BOT_TOKEN": "secret-token",
            "DISCORD_CHANNEL_ID": "111111",
            "MONITORING_API_BASE_URL": "http://monitor:4040/api",
        }

        with self.assertRaises(ValueError):
            BotConfig.from_env(env)

    def test_from_env_resolves_relative_cursor_file(self) -> None:
        env = {
            "DISCORD_BOT_TOKEN": "secret-token",
            "DISCORD_CHANNEL_ID": "111111",
            "MONITORING_API_BASE_URL": "http://monitor:4040/api",
            "ALERT_CONSUMER_API_TOKEN": "consumer-token",
            "DISCORD_ALERT_CURSOR_FILE": "state/cursor.json",
        }

        config = BotConfig.from_env(env)

        self.assertTrue(Path(config.discord_alert_cursor_file).is_absolute())
        self.assertTrue(config.discord_alert_cursor_file.endswith(str(Path("state") / "cursor.json")))


if __name__ == "__main__":
    unittest.main()
