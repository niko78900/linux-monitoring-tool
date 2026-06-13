from __future__ import annotations

import asyncio
import sys
import unittest
from pathlib import Path
from types import SimpleNamespace

SRC_DIR = Path(__file__).resolve().parents[1] / "src"
if str(SRC_DIR) not in sys.path:
    sys.path.insert(0, str(SRC_DIR))

if "discord" not in sys.modules:
    class _FakeColor:
        @staticmethod
        def green() -> int:
            return 0

        @staticmethod
        def orange() -> int:
            return 1

        @staticmethod
        def red() -> int:
            return 2

    class _FakeEmbed:
        def __init__(self, **kwargs: object) -> None:
            self.kwargs = kwargs
            self.fields: list[dict[str, object]] = []

        def add_field(self, **kwargs: object) -> None:
            self.fields.append(kwargs)

    sys.modules["discord"] = SimpleNamespace(
        Color=_FakeColor,
        Embed=_FakeEmbed,
        utils=SimpleNamespace(utcnow=lambda: None),
    )

from alert_state import AlertState  # noqa: E402
from monitoring_client import MonitoringAPIError  # noqa: E402
from services.alert_poller import run_alert_polling  # noqa: E402
from state.alert_cursor_store import AlertCursorStore  # noqa: E402


class FakeMonitoringClient:
    def __init__(
        self,
        *,
        events: list[dict[str, object]] | None = None,
        latest_event_id: int = 0,
        fail_health: bool = False,
    ) -> None:
        self.events = events or []
        self.latest_event_id = latest_event_id
        self.fail_health = fail_health
        self.after_ids: list[int] = []

    async def fetch_health(self) -> dict[str, object]:
        if self.fail_health:
            raise MonitoringAPIError("backend down")
        return {"status": "ok"}

    async def fetch_alert_status(self) -> dict[str, object]:
        return {"latest_event_id": self.latest_event_id}

    async def fetch_alert_events(self, *, after_id: int, limit: int) -> dict[str, object]:
        self.after_ids.append(after_id)
        return {"events": self.events, "latest_event_id": self.latest_event_id}


class FakeBot:
    def __init__(
        self,
        tmp_path: Path,
        *,
        events: list[dict[str, object]] | None = None,
        latest_event_id: int = 0,
        replay: bool = False,
        send_success: bool = True,
        fail_health: bool = False,
    ) -> None:
        self.config = SimpleNamespace(discord_alert_replay_on_first_start=replay)
        self.monitoring_client = FakeMonitoringClient(
            events=events,
            latest_event_id=latest_event_id,
            fail_health=fail_health,
        )
        self.backend_unreachable_state = AlertState()
        self.alert_cursor = AlertCursorStore(tmp_path / "cursor.json")
        self.alert_cursor.load()
        self.send_success = send_success
        self.sent_contexts: list[str] = []

    async def _resolve_alert_channel(self) -> object:
        return object()

    async def _safe_send_embed(self, *, channel: object, embed: object, context: str) -> bool:
        self.sent_contexts.append(context)
        return self.send_success


class AlertEventConsumerTests(unittest.TestCase):
    def test_first_start_without_replay_begins_at_latest_event(self) -> None:
        tmp_path = Path(self._testMethodName)
        tmp_path.mkdir(exist_ok=True)
        try:
            bot = FakeBot(
                tmp_path,
                latest_event_id=5,
                events=[
                    {
                        "event_id": 6,
                        "event_type": "active",
                        "severity": "warning",
                        "title": "CPU usage high",
                        "message": "92%",
                        "alert_key": "cpu-usage",
                    }
                ],
            )

            asyncio.run(run_alert_polling(bot))

            self.assertEqual(bot.monitoring_client.after_ids, [5])
            self.assertEqual(bot.alert_cursor.last_event_id, 6)
            self.assertEqual(bot.sent_contexts, ["backend-alert-event:6"])
        finally:
            for file in tmp_path.glob("*"):
                file.unlink()
            tmp_path.rmdir()

    def test_failed_discord_send_does_not_advance_cursor(self) -> None:
        tmp_path = Path(self._testMethodName)
        tmp_path.mkdir(exist_ok=True)
        try:
            bot = FakeBot(
                tmp_path,
                replay=True,
                send_success=False,
                events=[
                    {
                        "event_id": 1,
                        "event_type": "active",
                        "severity": "critical",
                        "title": "Memory usage high",
                        "message": "96%",
                        "alert_key": "memory-usage",
                    }
                ],
            )

            asyncio.run(run_alert_polling(bot))

            self.assertEqual(bot.alert_cursor.last_event_id, 0)
            self.assertEqual(bot.sent_contexts, ["backend-alert-event:1"])
        finally:
            for file in tmp_path.glob("*"):
                file.unlink()
            tmp_path.rmdir()

    def test_backend_unreachable_warning_is_local(self) -> None:
        tmp_path = Path(self._testMethodName)
        tmp_path.mkdir(exist_ok=True)
        try:
            bot = FakeBot(tmp_path, fail_health=True)

            asyncio.run(run_alert_polling(bot))
            asyncio.run(run_alert_polling(bot))

            self.assertEqual(bot.sent_contexts, ["alert:backend-unavailable"])
        finally:
            for file in tmp_path.glob("*"):
                file.unlink()
            tmp_path.rmdir()


if __name__ == "__main__":
    unittest.main()
