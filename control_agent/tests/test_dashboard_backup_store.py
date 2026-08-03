from __future__ import annotations

import os
from datetime import datetime, timedelta, timezone
from pathlib import Path
from uuid import uuid4

import pytest

from app.services.backup_store import BackupStore, BusyPlanError


def _store(path: Path, *, retention_records: int = 100) -> BackupStore:
    store = BackupStore(path, retention_records=retention_records, retention_days=90)
    store.initialize()
    return store


def _reserve(
    store: BackupStore,
    *,
    plan_id: str = "database",
    request_id: str | None = None,
    requested_at: datetime | None = None,
):
    return store.reserve(
        job_id=str(uuid4()),
        request_id=request_id or str(uuid4()),
        plan_id=plan_id,
        display_name="Database backup",
        reason="Controlled validation",
        source_address="192.0.2.10",
        requested_at=requested_at or datetime.now(timezone.utc),
    )


def _finish_success(store: BackupStore, job_id: str) -> None:
    store.mark_preparing(
        job_id,
        started_at=datetime.now(timezone.utc),
        source_size_estimate=1024,
    )
    store.mark_phase(job_id, "running")
    store.mark_phase(job_id, "verifying")
    store.finish(
        job_id,
        status="succeeded",
        finished_at=datetime.now(timezone.utc),
        duration_ms=10,
        summary="Backup completed and verification passed.",
        error_code=None,
        verification_state="passed",
        destination_snapshot="/mnt/storage/backups/database/2026-01-01T000000Z",
        manifest_path="/mnt/storage/backups/database/2026-01-01T000000Z/manifest.json",
        progress_percent=100,
        files_examined=1,
        files_copied=1,
        bytes_examined=1024,
        bytes_copied=1024,
    )


def test_database_is_durable_wal_and_integrity_checked(tmp_path: Path) -> None:
    path = tmp_path / "state" / "backups.db"
    store = _store(path)
    reservation = _reserve(store)
    _finish_success(store, str(reservation.record.job_id))

    reopened = _store(path)
    record = reopened.get(str(reservation.record.job_id))

    assert record is not None and record.status == "succeeded"
    assert reopened.quick_check() is True
    assert os.stat(path).st_mode & 0o777 == 0o640
    assert os.stat(path.parent).st_mode & 0o777 == 0o750


def test_duplicate_request_id_returns_original_job(tmp_path: Path) -> None:
    store = _store(tmp_path / "backups.db")
    request_id = str(uuid4())
    original = _reserve(store, request_id=request_id)
    duplicate = _reserve(store, request_id=request_id, plan_id="another")

    assert duplicate.duplicate is True
    assert duplicate.record.job_id == original.record.job_id
    assert duplicate.record.plan_id == "database"


def test_concurrent_same_plan_is_rejected_atomically(tmp_path: Path) -> None:
    store = _store(tmp_path / "backups.db")
    _reserve(store)

    with pytest.raises(BusyPlanError):
        _reserve(store)


def test_job_state_transitions_and_cancellation(tmp_path: Path) -> None:
    store = _store(tmp_path / "backups.db")
    reservation = _reserve(store)
    job_id = str(reservation.record.job_id)
    store.mark_preparing(job_id, started_at=datetime.now(timezone.utc), source_size_estimate=10)
    store.mark_phase(job_id, "running")
    cancellation = store.request_cancel(job_id, requested_at=datetime.now(timezone.utc))

    assert cancellation.helper_required is True
    assert cancellation.record.status == "cancel_requested"
    finished = store.finish(
        job_id,
        status="cancelled",
        finished_at=datetime.now(timezone.utc),
        duration_ms=10,
        summary="Backup cancelled by the operator.",
        error_code="cancelled_by_operator",
        verification_state="failed",
        destination_snapshot=None,
        manifest_path=None,
    )
    assert finished.status == "cancelled"
    assert finished.cancellation_requested is True


def test_timeout_is_a_terminal_state(tmp_path: Path) -> None:
    store = _store(tmp_path / "backups.db")
    reservation = _reserve(store)
    job_id = str(reservation.record.job_id)
    store.mark_preparing(job_id, started_at=datetime.now(timezone.utc), source_size_estimate=10)
    record = store.finish(
        job_id,
        status="timed_out",
        finished_at=datetime.now(timezone.utc),
        duration_ms=500,
        summary="Backup exceeded its execution deadline.",
        error_code="backup_timeout",
        verification_state="failed",
        destination_snapshot=None,
        manifest_path=None,
    )

    assert record.status == "timed_out"
    assert record.error_code == "backup_timeout"


def test_interrupted_job_recovery_marks_all_active_states_failed(tmp_path: Path) -> None:
    path = tmp_path / "backups.db"
    store = _store(path)
    first = _reserve(store, plan_id="one")
    second = _reserve(store, plan_id="two")
    store.mark_preparing(
        str(second.record.job_id),
        started_at=datetime.now(timezone.utc),
        source_size_estimate=10,
    )

    recovered = _store(path)
    assert recovered.recover_interrupted() == 2
    assert recovered.get(str(first.record.job_id)).error_code == "service_interrupted"
    assert recovered.get(str(second.record.job_id)).status == "failed"


def test_history_retention_never_touches_snapshot_paths(tmp_path: Path) -> None:
    store = _store(tmp_path / "backups.db", retention_records=2)
    snapshots: list[Path] = []
    now = datetime.now(timezone.utc)
    for index in range(4):
        reservation = _reserve(
            store,
            plan_id=f"plan-{index}",
            requested_at=now + timedelta(seconds=index),
        )
        snapshot = tmp_path / f"snapshot-{index}"
        snapshot.mkdir()
        snapshots.append(snapshot)
        _finish_success(store, str(reservation.record.job_id))

    store.prune()

    assert len(store.list(limit=10)) == 2
    assert all(snapshot.is_dir() for snapshot in snapshots)
