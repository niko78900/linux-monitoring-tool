from __future__ import annotations

import asyncio
import json
import sys
import unittest
from pathlib import Path

SRC_DIR = Path(__file__).resolve().parents[1] / "src"
if str(SRC_DIR) not in sys.path:
    sys.path.insert(0, str(SRC_DIR))

from alert_rules import Alert  # noqa: E402
from alert_state import AlertState  # noqa: E402
from mobile_push import (  # noqa: E402
    MobilePushDispatcher,
    MobilePushInstallation,
    MobilePushRegistry,
    MobilePushResult,
)


class FakeSender:
    def __init__(self, *, fail: bool = False, invalid_ids: tuple[str, ...] = ()) -> None:
        self.fail = fail
        self.invalid_ids = invalid_ids
        self.calls: list[dict[str, object]] = []

    def send(self, **kwargs):
        if self.fail:
            raise RuntimeError("firebase unavailable")
        self.calls.append(kwargs)
        installations = kwargs["installations"]
        return MobilePushResult(
            sent_count=len(installations),
            invalid_installation_ids=self.invalid_ids,
        )


def _registry(tmp_path: Path) -> MobilePushRegistry:
    path = tmp_path / "tokens.json"
    path.write_text(
        json.dumps(
            {
                "installations": [
                    {
                        "installation_id": "tablet-1",
                        "device_name": "Homelab Tablet",
                        "fcm_token": "token",
                        "platform": "android",
                        "enabled": True,
                        "last_registered_at": "2026-06-12T00:00:00+00:00",
                    }
                ]
            }
        ),
        encoding="utf-8",
    )
    return MobilePushRegistry(path)


class MobilePushTests(unittest.TestCase):
    def test_dispatcher_sends_only_mobile_scoped_alerts(self) -> None:
        temp_dir = Path(self._testMethodName)
        temp_dir.mkdir(exist_ok=True)
        try:
            sender = FakeSender()
            dispatcher = MobilePushDispatcher(
                enabled=True,
                include_recovery=True,
                registry=_registry(temp_dir),
                sender=sender,
            )
            asyncio.run(
                dispatcher.dispatch(
                    alerts=[
                        Alert("cpu-usage", "CPU usage high", "92% is above threshold.", "warning"),
                        Alert("docker-unavailable", "Docker unavailable", "down", "warning"),
                    ],
                    recoveries=[],
                )
            )

            self.assertEqual(len(sender.calls), 1)
            self.assertEqual(sender.calls[0]["title"], "High CPU usage")
            self.assertEqual(sender.calls[0]["route"], "/overview")
        finally:
            for file in temp_dir.glob("*"):
                file.unlink()
            temp_dir.rmdir()

    def test_alert_state_dedup_prevents_repeated_mobile_push(self) -> None:
        state = AlertState(default_notify_after_seconds=0)
        alert = Alert("memory-usage", "Memory usage high", "94%", "warning")

        first, _ = state.transition([alert])
        second, _ = state.transition([alert])

        self.assertEqual(len(first), 1)
        self.assertEqual(len(second), 0)

    def test_recovery_can_be_sent_or_suppressed(self) -> None:
        temp_dir = Path(self._testMethodName)
        temp_dir.mkdir(exist_ok=True)
        try:
            state = AlertState(default_notify_after_seconds=0)
            alert = Alert("disk-usage:/mnt/warm", "Disk usage high", "91%", "warning")
            state.transition([alert])
            _, recoveries = state.transition([])

            enabled_sender = FakeSender()
            enabled_dispatcher = MobilePushDispatcher(
                enabled=True,
                include_recovery=True,
                registry=_registry(temp_dir),
                sender=enabled_sender,
            )
            asyncio.run(enabled_dispatcher.dispatch(alerts=[], recoveries=recoveries))
            self.assertEqual(len(enabled_sender.calls), 1)
            self.assertEqual(enabled_sender.calls[0]["title"], "Storage recovered")

            disabled_sender = FakeSender()
            disabled_dispatcher = MobilePushDispatcher(
                enabled=True,
                include_recovery=False,
                registry=_registry(temp_dir),
                sender=disabled_sender,
            )
            asyncio.run(disabled_dispatcher.dispatch(alerts=[], recoveries=recoveries))
            self.assertEqual(len(disabled_sender.calls), 0)
        finally:
            for file in temp_dir.glob("*"):
                file.unlink()
            temp_dir.rmdir()

    def test_invalid_installation_is_disabled(self) -> None:
        temp_dir = Path(self._testMethodName)
        temp_dir.mkdir(exist_ok=True)
        try:
            registry = _registry(temp_dir)
            dispatcher = MobilePushDispatcher(
                enabled=True,
                include_recovery=True,
                registry=registry,
                sender=FakeSender(invalid_ids=("tablet-1",)),
            )
            asyncio.run(
                dispatcher.dispatch(
                    alerts=[Alert("gpu-usage", "GPU usage high", "96%", "warning")],
                    recoveries=[],
                )
            )

            self.assertEqual(registry.enabled_installations(), [])
        finally:
            for file in temp_dir.glob("*"):
                file.unlink()
            temp_dir.rmdir()

    def test_firebase_failure_does_not_escape_dispatcher(self) -> None:
        temp_dir = Path(self._testMethodName)
        temp_dir.mkdir(exist_ok=True)
        try:
            dispatcher = MobilePushDispatcher(
                enabled=True,
                include_recovery=True,
                registry=_registry(temp_dir),
                sender=FakeSender(fail=True),
            )

            asyncio.run(
                dispatcher.dispatch(
                    alerts=[Alert("cpu-usage", "CPU usage high", "92%", "warning")],
                    recoveries=[],
                )
            )
        finally:
            for file in temp_dir.glob("*"):
                file.unlink()
            temp_dir.rmdir()


if __name__ == "__main__":
    unittest.main()
