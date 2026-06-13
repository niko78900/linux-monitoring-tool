from __future__ import annotations

import json
import logging
from dataclasses import dataclass
from pathlib import Path

logger = logging.getLogger("linux_monitoring.bot")


@dataclass
class AlertCursorStore:
    path: Path
    last_event_id: int | None = None

    def load(self) -> None:
        if not self.path.exists():
            self.last_event_id = None
            return
        try:
            payload = json.loads(self.path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            logger.warning("Could not read alert cursor from %s: %s", self.path, exc)
            self.last_event_id = None
            return
        if not isinstance(payload, dict):
            self.last_event_id = None
            return
        raw_value = payload.get("last_event_id")
        try:
            self.last_event_id = max(0, int(raw_value))
        except (TypeError, ValueError):
            self.last_event_id = None

    def save(self, last_event_id: int) -> None:
        self.last_event_id = max(0, int(last_event_id))
        payload = json.dumps(
            {"last_event_id": self.last_event_id},
            separators=(",", ":"),
            sort_keys=True,
        )
        try:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            tmp_path = self.path.with_name(self.path.name + ".tmp")
            tmp_path.write_text(payload, encoding="utf-8")
            tmp_path.replace(self.path)
        except OSError as exc:
            logger.warning("Could not persist alert cursor to %s: %s", self.path, exc)
