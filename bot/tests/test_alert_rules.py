from __future__ import annotations

import sys
import unittest
from pathlib import Path

SRC_DIR = Path(__file__).resolve().parents[1] / "src"
if str(SRC_DIR) not in sys.path:
    sys.path.insert(0, str(SRC_DIR))

from alert_rules import evaluate_alerts  # noqa: E402
from config import BotConfig  # noqa: E402


def _config() -> BotConfig:
    return BotConfig.from_env(
        {
            "DISCORD_BOT_TOKEN": "token",
            "DISCORD_CHANNEL_ID": "123",
            "MONITOR_API_BASE_URL": "http://monitor:4040",
        }
    )


class AlertRulesTests(unittest.TestCase):
    def test_gpu_usage_alert_is_evaluated(self) -> None:
        alerts = evaluate_alerts(
            config=_config(),
            health={"status": "ok"},
            summary=None,
            system=None,
            gpu={"available": True, "utilization_percent": 96, "temperature_c": 40},
            docker=None,
        )

        self.assertEqual([alert.key for alert in alerts], ["gpu-usage"])

    def test_docker_and_raid_alerts_remain_non_mobile_policy_inputs(self) -> None:
        alerts = evaluate_alerts(
            config=_config(),
            health={"status": "ok"},
            summary=None,
            system={
                "raid_arrays": [
                    {"name": "md0", "health": {"status": "warning", "reason": "degraded"}}
                ]
            },
            gpu=None,
            docker={"docker_available": False, "reason": "down"},
        )

        self.assertIn("docker-unavailable", [alert.key for alert in alerts])
        self.assertIn("raid-health:md0", [alert.key for alert in alerts])


if __name__ == "__main__":
    unittest.main()
