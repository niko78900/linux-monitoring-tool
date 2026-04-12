from __future__ import annotations

import json
import logging
from pathlib import Path

from alert_state import AlertState

logger = logging.getLogger("linux_monitoring.bot")


def load_alert_state(path: Path, alert_state: AlertState) -> None:
    if not path.exists():
        return

    try:
        raw_text = path.read_text(encoding="utf-8")
        payload = json.loads(raw_text)
    except (OSError, json.JSONDecodeError) as exc:
        logger.warning("Could not read alert state from %s: %s", path, exc)
        return

    if not isinstance(payload, dict):
        logger.warning("Alert state file is not an object: %s", path)
        return

    alert_state.load_snapshot(payload)
    logger.info("Loaded alert state with %s active alert(s).", alert_state.active_count)


def save_alert_state(path: Path, alert_state: AlertState) -> None:
    if alert_state.active_count == 0:
        try:
            if path.exists():
                path.unlink()
        except OSError as exc:
            logger.warning("Could not clear alert state at %s: %s", path, exc)
        return

    payload = alert_state.to_snapshot()
    serialized = json.dumps(payload, separators=(",", ":"), sort_keys=True)

    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp_path = path.with_name(path.name + ".tmp")
        tmp_path.write_text(serialized, encoding="utf-8")
        tmp_path.replace(path)
    except OSError as exc:
        logger.warning("Could not persist alert state to %s: %s", path, exc)
