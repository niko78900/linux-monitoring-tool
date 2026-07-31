from __future__ import annotations

import os
from datetime import datetime, timedelta, timezone
from pathlib import Path
from uuid import uuid4

import pytest

from app.services.action_store import ActionStore, BusyTargetError


def _store(path: Path, *, retention_records: int = 100) -> ActionStore:
    store = ActionStore(
        path,
        retention_records=retention_records,
        retention_days=90,
    )
    store.initialize()
    return store


def _reserve(
    store: ActionStore,
    *,
    target_id: str = "example-worker",
    request_id: str | None = None,
    requested_at: datetime | None = None,
):
    return store.reserve(
        action_id=str(uuid4()),
        request_id=request_id or str(uuid4()),
        caller="homelab-dashboard",
        source_address="192.0.2.10",
        target_id=target_id,
        display_name="Example Worker",
        action="restart",
        reason="Controlled validation",
        requested_at=requested_at or datetime.now(timezone.utc),
    )


def _finish(store: ActionStore, action_id: str) -> None:
    store.mark_running(action_id, started_at=datetime.now(timezone.utc))
    store.finish(
        action_id,
        status="succeeded",
        finished_at=datetime.now(timezone.utc),
        result_summary="Action completed.",
        error_code=None,
        duration_ms=10,
        previous_state="running",
        resulting_state="running",
    )


def test_database_is_durable_and_integrity_checked(tmp_path: Path) -> None:
    path = tmp_path / "actions.db"
    first_store = _store(path)
    reservation = _reserve(first_store)
    _finish(first_store, str(reservation.record.action_id))

    second_store = _store(path)
    persisted = second_store.get(str(reservation.record.action_id))

    assert persisted is not None
    assert persisted.status == "succeeded"
    assert second_store.quick_check() is True
    assert os.stat(path).st_mode & 0o777 == 0o640


def test_request_id_is_idempotent(tmp_path: Path) -> None:
    store = _store(tmp_path / "actions.db")
    request_id = str(uuid4())
    original = _reserve(store, request_id=request_id)
    duplicate = _reserve(store, request_id=request_id, target_id="other-worker")

    assert original.duplicate is False
    assert duplicate.duplicate is True
    assert duplicate.record.action_id == original.record.action_id
    assert duplicate.record.target_id == "example-worker"


def test_one_active_action_per_target(tmp_path: Path) -> None:
    store = _store(tmp_path / "actions.db")
    _reserve(store)

    with pytest.raises(BusyTargetError):
        _reserve(store)


def test_database_restart_recovery_marks_active_records_failed(tmp_path: Path) -> None:
    path = tmp_path / "actions.db"
    store = _store(path)
    queued = _reserve(store)

    recovered_store = _store(path)
    assert recovered_store.recover_interrupted() == 1
    record = recovered_store.get(str(queued.record.action_id))

    assert record is not None
    assert record.status == "failed"
    assert record.error_code == "action_service_restarted"


def test_bounded_retention_keeps_newest_terminal_records(tmp_path: Path) -> None:
    store = _store(tmp_path / "actions.db", retention_records=2)
    identifiers: list[str] = []
    now = datetime.now(timezone.utc)
    for index in range(4):
        reservation = _reserve(
            store,
            target_id=f"worker-{index}",
            requested_at=now + timedelta(seconds=index),
        )
        identifiers.append(str(reservation.record.action_id))
        _finish(store, identifiers[-1])

    store.prune()
    retained = {str(record.action_id) for record in store.list(limit=10)}

    assert retained == set(identifiers[-2:])
