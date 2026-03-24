from __future__ import annotations

import sys
import unittest
from datetime import datetime, timezone
from pathlib import Path

SRC_DIR = Path(__file__).resolve().parents[1] / "src"
if str(SRC_DIR) not in sys.path:
    sys.path.insert(0, str(SRC_DIR))

from schedule_policy import (  # noqa: E402
    compute_next_event,
    parse_windows_payload,
    parse_windows_spec,
    serialize_windows_payload,
)


class SchedulePolicyTests(unittest.TestCase):
    def test_parse_windows_spec_supports_multiple_windows(self) -> None:
        windows = parse_windows_spec(
            "12:00-15:00=15;15:00-18:00=60;18:00-21:00=45;21:00-06:00=360",
            min_interval_minutes=5,
            max_interval_minutes=1440,
            max_rules=24,
        )

        self.assertEqual(len(windows), 4)
        self.assertEqual(windows[0].start_minute, 12 * 60)
        self.assertEqual(windows[0].end_minute, 15 * 60)
        self.assertEqual(windows[0].interval_seconds, 15 * 60)
        self.assertEqual(windows[3].start_minute, 21 * 60)
        self.assertEqual(windows[3].end_minute, 6 * 60)
        self.assertEqual(windows[3].interval_seconds, 360 * 60)

    def test_parse_windows_spec_rejects_overlap(self) -> None:
        with self.assertRaises(ValueError):
            parse_windows_spec(
                "12:00-15:00=15;14:30-16:00=60",
                min_interval_minutes=5,
                max_interval_minutes=1440,
                max_rules=24,
            )

    def test_payload_round_trip(self) -> None:
        original = parse_windows_spec(
            "08:00-12:00=30;12:00-18:00=60;18:00-08:00=180",
            min_interval_minutes=5,
            max_interval_minutes=1440,
            max_rules=24,
        )
        payload = serialize_windows_payload(original)
        parsed = parse_windows_payload(
            payload,
            min_interval_seconds=5 * 60,
            max_interval_seconds=1440 * 60,
        )
        self.assertEqual(original, parsed)

    def test_compute_next_event_fixed_mode_posts_after_interval(self) -> None:
        now = datetime(2026, 3, 24, 12, 0, tzinfo=timezone.utc)
        event = compute_next_event(
            mode="fixed",
            now_utc=now,
            fixed_interval_seconds=900,
            windows=[],
            local_tz=timezone.utc,
        )
        self.assertIsNotNone(event)
        assert event is not None
        self.assertTrue(event.should_send)
        self.assertEqual(event.run_at_utc, datetime(2026, 3, 24, 12, 15, tzinfo=timezone.utc))

    def test_compute_next_event_windows_mode_posts_within_window(self) -> None:
        windows = parse_windows_spec(
            "12:00-15:00=15;15:00-18:00=60;18:00-21:00=45;21:00-06:00=360",
            min_interval_minutes=5,
            max_interval_minutes=1440,
            max_rules=24,
        )
        now = datetime(2026, 3, 24, 12, 10, tzinfo=timezone.utc)
        event = compute_next_event(
            mode="windows",
            now_utc=now,
            fixed_interval_seconds=900,
            windows=windows,
            local_tz=timezone.utc,
        )
        self.assertIsNotNone(event)
        assert event is not None
        self.assertTrue(event.should_send)
        self.assertEqual(event.run_at_utc, datetime(2026, 3, 24, 12, 25, tzinfo=timezone.utc))

    def test_compute_next_event_windows_mode_moves_to_boundary_without_post(self) -> None:
        windows = parse_windows_spec(
            "12:00-15:00=15;15:00-18:00=60;18:00-21:00=45;21:00-06:00=360",
            min_interval_minutes=5,
            max_interval_minutes=1440,
            max_rules=24,
        )
        now = datetime(2026, 3, 24, 14, 50, tzinfo=timezone.utc)
        event = compute_next_event(
            mode="windows",
            now_utc=now,
            fixed_interval_seconds=900,
            windows=windows,
            local_tz=timezone.utc,
        )
        self.assertIsNotNone(event)
        assert event is not None
        self.assertFalse(event.should_send)
        self.assertEqual(event.run_at_utc, datetime(2026, 3, 24, 15, 0, tzinfo=timezone.utc))

    def test_compute_next_event_windows_mode_waits_for_next_start_when_outside_windows(self) -> None:
        windows = parse_windows_spec(
            "12:00-15:00=15;15:00-18:00=60;18:00-21:00=45;21:00-06:00=360",
            min_interval_minutes=5,
            max_interval_minutes=1440,
            max_rules=24,
        )
        now = datetime(2026, 3, 24, 7, 0, tzinfo=timezone.utc)
        event = compute_next_event(
            mode="windows",
            now_utc=now,
            fixed_interval_seconds=900,
            windows=windows,
            local_tz=timezone.utc,
        )
        self.assertIsNotNone(event)
        assert event is not None
        self.assertFalse(event.should_send)
        self.assertEqual(event.run_at_utc, datetime(2026, 3, 24, 12, 0, tzinfo=timezone.utc))


if __name__ == "__main__":
    unittest.main()
