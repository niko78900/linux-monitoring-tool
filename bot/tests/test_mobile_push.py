from __future__ import annotations

import asyncio
import json
import os
import sys
import time
import unittest
from pathlib import Path

SRC_DIR = Path(__file__).resolve().parents[1] / "src"
if str(SRC_DIR) not in sys.path:
    sys.path.insert(0, str(SRC_DIR))

from alert_rules import Alert  # noqa: E402
from alert_state import AlertState, RecoveryNotice  # noqa: E402
from mobile_push import (  # noqa: E402
    MobilePushDispatcher,
    MobilePushDeliveryOutbox,
    MobilePushInstallation,
    MobilePushRegistry,
    MobilePushResult,
)


class FakeSender:
    def __init__(
        self,
        *,
        fail: bool = False,
        invalid_ids: tuple[str, ...] = (),
        fail_ids: tuple[str, ...] = (),
        delay: float = 0.0,
    ) -> None:
        self.fail = fail
        self.invalid_ids = invalid_ids
        self.fail_ids = fail_ids
        self.delay = delay
        self.calls: list[dict[str, object]] = []

    def send(self, **kwargs):
        if self.delay:
            time.sleep(self.delay)
        if self.fail:
            raise RuntimeError("firebase unavailable")
        self.calls.append(kwargs)
        installations = kwargs["installations"]
        sent_installation_ids = tuple(
            installation.installation_id
            for installation in installations
            if installation.installation_id not in self.fail_ids
        )
        return MobilePushResult(
            sent_count=len(sent_installation_ids),
            failed_count=len(installations) - len(sent_installation_ids),
            invalid_installation_ids=self.invalid_ids,
            sent_installation_ids=sent_installation_ids,
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
                        "include_recovery": True,
                        "last_registered_at": "2026-06-12T00:00:00+00:00",
                    }
                ]
            }
        ),
        encoding="utf-8",
    )
    return MobilePushRegistry(path)


def _outbox(tmp_path: Path) -> MobilePushDeliveryOutbox:
    return MobilePushDeliveryOutbox(
        tmp_path / "outbox.json",
        retry_initial_seconds=0,
        retry_max_seconds=1,
    )


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
                outbox=_outbox(temp_dir),
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
                outbox=_outbox(temp_dir),
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
                outbox=_outbox(temp_dir),
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
                outbox=_outbox(temp_dir),
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
                outbox=_outbox(temp_dir),
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

    def test_temporary_failure_stays_pending_and_retries(self) -> None:
        temp_dir = Path(self._testMethodName)
        temp_dir.mkdir(exist_ok=True)
        try:
            outbox = _outbox(temp_dir)
            sender = FakeSender(fail=True)
            dispatcher = MobilePushDispatcher(
                enabled=True,
                include_recovery=True,
                registry=_registry(temp_dir),
                sender=sender,
                outbox=outbox,
            )

            asyncio.run(
                dispatcher.dispatch(
                    alerts=[Alert("cpu-usage", "CPU usage high", "92%", "warning")],
                    recoveries=[],
                )
            )
            self.assertEqual(outbox.pending_count(), 1)
            if os.name != "nt":
                self.assertEqual((temp_dir / "outbox.json").stat().st_mode & 0o777, 0o640)

            sender.fail = False
            asyncio.run(dispatcher.dispatch(alerts=[], recoveries=[]))

            self.assertEqual(outbox.pending_count(), 0)
            self.assertEqual(len(sender.calls), 1)
            asyncio.run(dispatcher.dispatch(alerts=[], recoveries=[]))
            self.assertEqual(len(sender.calls), 1)
        finally:
            for file in temp_dir.glob("*"):
                file.unlink()
            temp_dir.rmdir()

    def test_delivered_entry_can_be_requeued_for_later_alert_cycle(self) -> None:
        temp_dir = Path(self._testMethodName)
        temp_dir.mkdir(exist_ok=True)
        try:
            outbox = _outbox(temp_dir)
            sender = FakeSender()
            dispatcher = MobilePushDispatcher(
                enabled=True,
                include_recovery=True,
                registry=_registry(temp_dir),
                sender=sender,
                outbox=outbox,
            )
            alert = Alert("cpu-usage", "CPU usage high", "92%", "warning")

            asyncio.run(dispatcher.dispatch(alerts=[alert], recoveries=[]))
            asyncio.run(dispatcher.dispatch(alerts=[alert], recoveries=[]))

            self.assertEqual(outbox.pending_count(), 0)
            self.assertEqual(len(sender.calls), 2)
        finally:
            for file in temp_dir.glob("*"):
                file.unlink()
            temp_dir.rmdir()

    def test_pending_outbox_survives_dispatcher_restart(self) -> None:
        temp_dir = Path(self._testMethodName)
        temp_dir.mkdir(exist_ok=True)
        try:
            outbox_path = temp_dir / "outbox.json"
            first_sender = FakeSender(fail=True)
            first = MobilePushDispatcher(
                enabled=True,
                include_recovery=True,
                registry=_registry(temp_dir),
                sender=first_sender,
                outbox=MobilePushDeliveryOutbox(
                    outbox_path,
                    retry_initial_seconds=0,
                    retry_max_seconds=1,
                ),
            )
            asyncio.run(
                first.dispatch(
                    alerts=[Alert("memory-usage", "Memory usage high", "94%", "warning")],
                    recoveries=[],
                )
            )

            second_sender = FakeSender()
            second = MobilePushDispatcher(
                enabled=True,
                include_recovery=True,
                registry=_registry(temp_dir),
                sender=second_sender,
                outbox=MobilePushDeliveryOutbox(
                    outbox_path,
                    retry_initial_seconds=0,
                    retry_max_seconds=1,
                ),
            )
            asyncio.run(second.dispatch(alerts=[], recoveries=[]))

            self.assertEqual(len(second_sender.calls), 1)
            self.assertEqual(
                MobilePushDeliveryOutbox(outbox_path).pending_count(),
                0,
            )
        finally:
            for file in temp_dir.glob("*"):
                file.unlink()
            temp_dir.rmdir()

    def test_partial_delivery_retry_skips_already_delivered_installation(self) -> None:
        temp_dir = Path(self._testMethodName)
        temp_dir.mkdir(exist_ok=True)
        try:
            registry_path = temp_dir / "tokens.json"
            registry_path.write_text(
                json.dumps(
                    {
                        "installations": [
                            {
                                "installation_id": "tablet-1",
                                "device_name": "One",
                                "fcm_token": "token-1",
                                "platform": "android",
                                "enabled": True,
                                "include_recovery": True,
                                "last_registered_at": "2026-06-12T00:00:00+00:00",
                            },
                            {
                                "installation_id": "tablet-2",
                                "device_name": "Two",
                                "fcm_token": "token-2",
                                "platform": "android",
                                "enabled": True,
                                "include_recovery": True,
                                "last_registered_at": "2026-06-12T00:00:00+00:00",
                            },
                        ]
                    }
                ),
                encoding="utf-8",
            )
            outbox = _outbox(temp_dir)
            sender = FakeSender(fail_ids=("tablet-2",))
            dispatcher = MobilePushDispatcher(
                enabled=True,
                include_recovery=True,
                registry=MobilePushRegistry(registry_path),
                sender=sender,
                outbox=outbox,
            )
            asyncio.run(
                dispatcher.dispatch(
                    alerts=[Alert("gpu-usage", "GPU usage high", "96%", "warning")],
                    recoveries=[],
                )
            )

            sender.fail_ids = ()
            asyncio.run(dispatcher.dispatch(alerts=[], recoveries=[]))

            first_call_ids = [
                item.installation_id for item in sender.calls[0]["installations"]
            ]
            retry_call_ids = [
                item.installation_id for item in sender.calls[1]["installations"]
            ]
            self.assertEqual(first_call_ids, ["tablet-1", "tablet-2"])
            self.assertEqual(retry_call_ids, ["tablet-2"])
            self.assertEqual(outbox.pending_count(), 0)
        finally:
            for file in temp_dir.glob("*"):
                file.unlink()
            temp_dir.rmdir()

    def test_recovery_preference_is_per_installation(self) -> None:
        temp_dir = Path(self._testMethodName)
        temp_dir.mkdir(exist_ok=True)
        try:
            registry_path = temp_dir / "tokens.json"
            registry_path.write_text(
                json.dumps(
                    {
                        "installations": [
                            {
                                "installation_id": "tablet-1",
                                "device_name": "One",
                                "fcm_token": "token-1",
                                "platform": "android",
                                "enabled": True,
                                "include_recovery": True,
                                "last_registered_at": "2026-06-12T00:00:00+00:00",
                            },
                            {
                                "installation_id": "tablet-2",
                                "device_name": "Two",
                                "fcm_token": "token-2",
                                "platform": "android",
                                "enabled": True,
                                "include_recovery": False,
                                "last_registered_at": "2026-06-12T00:00:00+00:00",
                            },
                        ]
                    }
                ),
                encoding="utf-8",
            )
            sender = FakeSender()
            dispatcher = MobilePushDispatcher(
                enabled=True,
                include_recovery=True,
                registry=MobilePushRegistry(registry_path),
                sender=sender,
                outbox=_outbox(temp_dir),
            )

            asyncio.run(
                dispatcher.dispatch(
                    alerts=[],
                    recoveries=[
                        RecoveryNotice(
                            key="cpu-usage",
                            title="CPU usage high",
                            message="recovered",
                            was_active_for_seconds=60,
                        )
                    ],
                )
            )

            sent_to = sender.calls[0]["installations"]
            self.assertEqual([item.installation_id for item in sent_to], ["tablet-1"])
        finally:
            for file in temp_dir.glob("*"):
                file.unlink()
            temp_dir.rmdir()

    def test_global_recovery_switch_suppresses_pending_recovery(self) -> None:
        temp_dir = Path(self._testMethodName)
        temp_dir.mkdir(exist_ok=True)
        try:
            outbox = _outbox(temp_dir)
            failing_sender = FakeSender(fail=True)
            enabled = MobilePushDispatcher(
                enabled=True,
                include_recovery=True,
                registry=_registry(temp_dir),
                sender=failing_sender,
                outbox=outbox,
            )
            recovery = RecoveryNotice(
                key="cpu-usage",
                title="CPU usage high",
                message="recovered",
                was_active_for_seconds=60,
            )
            asyncio.run(enabled.dispatch(alerts=[], recoveries=[recovery]))
            self.assertEqual(outbox.pending_count(), 1)

            suppressed_sender = FakeSender()
            disabled = MobilePushDispatcher(
                enabled=True,
                include_recovery=False,
                registry=_registry(temp_dir),
                sender=suppressed_sender,
                outbox=outbox,
            )
            asyncio.run(disabled.dispatch(alerts=[], recoveries=[]))

            self.assertEqual(len(suppressed_sender.calls), 0)
            self.assertEqual(outbox.pending_count(), 0)
        finally:
            for file in temp_dir.glob("*"):
                file.unlink()
            temp_dir.rmdir()

    def test_slow_sender_runs_off_event_loop(self) -> None:
        temp_dir = Path(self._testMethodName)
        temp_dir.mkdir(exist_ok=True)
        try:
            dispatcher = MobilePushDispatcher(
                enabled=True,
                include_recovery=True,
                registry=_registry(temp_dir),
                sender=FakeSender(delay=0.1),
                outbox=_outbox(temp_dir),
            )

            async def run() -> float:
                task = asyncio.create_task(
                    dispatcher.dispatch(
                        alerts=[
                            Alert(
                                "cpu-usage",
                                "CPU usage high",
                                "92%",
                                "warning",
                            )
                        ],
                        recoveries=[],
                    )
                )
                started = time.perf_counter()
                await asyncio.sleep(0.01)
                elapsed = time.perf_counter() - started
                await task
                return elapsed

            self.assertLess(asyncio.run(run()), 0.08)
        finally:
            for file in temp_dir.glob("*"):
                file.unlink()
            temp_dir.rmdir()


if __name__ == "__main__":
    unittest.main()
