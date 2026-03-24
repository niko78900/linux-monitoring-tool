from __future__ import annotations

import sys
import unittest
from pathlib import Path

SRC_DIR = Path(__file__).resolve().parents[1] / "src"
if str(SRC_DIR) not in sys.path:
    sys.path.insert(0, str(SRC_DIR))

from alert_rules import Alert  # noqa: E402
from alert_state import AlertState  # noqa: E402


class AlertStateTests(unittest.TestCase):
    def test_deduplicates_active_alerts_and_emits_recovery(self) -> None:
        state = AlertState()
        cpu_alert = Alert(
            key="cpu-usage",
            title="CPU usage high",
            message="CPU is above threshold.",
            severity="warning",
        )

        new_alerts, recoveries = state.transition([cpu_alert])
        self.assertEqual(len(new_alerts), 1)
        self.assertEqual(len(recoveries), 0)
        self.assertEqual(state.active_count, 1)

        new_alerts, recoveries = state.transition([cpu_alert])
        self.assertEqual(len(new_alerts), 0)
        self.assertEqual(len(recoveries), 0)
        self.assertEqual(state.active_count, 1)

        new_alerts, recoveries = state.transition([])
        self.assertEqual(len(new_alerts), 0)
        self.assertEqual(len(recoveries), 1)
        self.assertEqual(recoveries[0].key, "cpu-usage")
        self.assertEqual(state.active_count, 0)

    def test_message_update_while_active_does_not_realert(self) -> None:
        state = AlertState()
        first = Alert(key="disk-usage:/", title="Disk usage high", message="90%", severity="warning")
        second = Alert(key="disk-usage:/", title="Disk usage high", message="95%", severity="critical")

        new_alerts, recoveries = state.transition([first])
        self.assertEqual(len(new_alerts), 1)
        self.assertEqual(len(recoveries), 0)

        new_alerts, recoveries = state.transition([second])
        self.assertEqual(len(new_alerts), 0)
        self.assertEqual(len(recoveries), 0)

    def test_snapshot_round_trip_preserves_active_dedupe_keys(self) -> None:
        state = AlertState()
        cpu_alert = Alert(key="cpu-usage", title="CPU usage high", message="92%", severity="warning")
        mem_alert = Alert(key="memory-usage", title="Memory usage high", message="95%", severity="critical")
        state.transition([cpu_alert, mem_alert])
        snapshot = state.to_snapshot()

        restored = AlertState()
        restored.load_snapshot(snapshot)

        new_alerts, recoveries = restored.transition([cpu_alert, mem_alert])
        self.assertEqual(len(new_alerts), 0)
        self.assertEqual(len(recoveries), 0)

        new_alerts, recoveries = restored.transition([])
        self.assertEqual(len(new_alerts), 0)
        self.assertEqual(len(recoveries), 2)


if __name__ == "__main__":
    unittest.main()
