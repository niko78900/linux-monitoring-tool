from __future__ import annotations

import sys
import unittest
from pathlib import Path

SRC_DIR = Path(__file__).resolve().parents[1] / "src"
if str(SRC_DIR) not in sys.path:
    sys.path.insert(0, str(SRC_DIR))

from alert_rules import evaluate_alerts  # noqa: E402


class AlertRulesTests(unittest.TestCase):
    def test_only_backend_unreachable_is_evaluated_locally(self) -> None:
        alerts = evaluate_alerts(
            backend_error=None,
            summary={"cpu_percent": 99, "memory_percent": 99},
            system={"disks": [{"mountpoint": "/", "percent": 99}]},
            gpu={"available": True, "utilization_percent": 99},
            docker={"docker_available": False},
        )

        self.assertEqual(alerts, [])

    def test_backend_unreachable_warning_remains_discord_local(self) -> None:
        alerts = evaluate_alerts(backend_error="health endpoint is unavailable.")

        self.assertEqual([alert.key for alert in alerts], ["backend-unavailable"])


if __name__ == "__main__":
    unittest.main()
