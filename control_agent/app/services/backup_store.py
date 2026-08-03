from __future__ import annotations

import os
import re
import sqlite3
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path

from ..models.dashboard_backups import BackupJobResponse, BackupJobStatus

ACTIVE_STATES = (
    "queued",
    "preparing",
    "running",
    "verifying",
    "cancel_requested",
)
TERMINAL_STATES = (
    "succeeded",
    "failed",
    "cancelled",
    "timed_out",
    "rejected",
)
ERROR_CODE_PATTERN = re.compile(r"^[a-z0-9_]{1,64}$")


class BusyPlanError(RuntimeError):
    pass


class JobTransitionError(RuntimeError):
    pass


class JobNotFoundError(RuntimeError):
    pass


class CannotCancelError(RuntimeError):
    pass


@dataclass(frozen=True)
class JobReservation:
    record: BackupJobResponse
    duplicate: bool


@dataclass(frozen=True)
class CancellationResult:
    record: BackupJobResponse
    helper_required: bool


class BackupStore:
    def __init__(
        self,
        path: Path,
        *,
        retention_records: int,
        retention_days: int,
    ):
        self.path = path
        self.retention_records = retention_records
        self.retention_days = retention_days

    def initialize(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        os.chmod(self.path.parent, 0o750)
        with self._connect() as connection:
            connection.executescript(
                """
                CREATE TABLE IF NOT EXISTS dashboard_backup_jobs (
                    job_id TEXT PRIMARY KEY,
                    request_id TEXT NOT NULL UNIQUE,
                    plan_id TEXT NOT NULL,
                    display_name TEXT NOT NULL,
                    status TEXT NOT NULL,
                    reason TEXT,
                    source_address TEXT NOT NULL,
                    requested_at TEXT NOT NULL,
                    started_at TEXT,
                    finished_at TEXT,
                    current_phase TEXT NOT NULL,
                    progress_percent REAL,
                    files_examined INTEGER,
                    files_copied INTEGER,
                    bytes_examined INTEGER,
                    bytes_copied INTEGER,
                    source_size_estimate INTEGER,
                    destination_snapshot TEXT,
                    duration_ms INTEGER,
                    verification_state TEXT NOT NULL DEFAULT 'pending',
                    manifest_path TEXT,
                    result_summary TEXT,
                    error_code TEXT,
                    cancellation_requested INTEGER NOT NULL DEFAULT 0,
                    CHECK (status IN (
                        'queued', 'preparing', 'running', 'verifying',
                        'succeeded', 'failed', 'cancel_requested', 'cancelled',
                        'timed_out', 'rejected'
                    )),
                    CHECK (verification_state IN (
                        'pending', 'passed', 'failed', 'not_applicable'
                    )),
                    CHECK (cancellation_requested IN (0, 1)),
                    CHECK (progress_percent IS NULL OR
                           (progress_percent >= 0 AND progress_percent <= 100)),
                    CHECK (files_examined IS NULL OR files_examined >= 0),
                    CHECK (files_copied IS NULL OR files_copied >= 0),
                    CHECK (bytes_examined IS NULL OR bytes_examined >= 0),
                    CHECK (bytes_copied IS NULL OR bytes_copied >= 0),
                    CHECK (source_size_estimate IS NULL OR source_size_estimate >= 0),
                    CHECK (duration_ms IS NULL OR duration_ms >= 0)
                );
                CREATE INDEX IF NOT EXISTS idx_dashboard_backup_jobs_requested
                    ON dashboard_backup_jobs(requested_at DESC, job_id DESC);
                CREATE INDEX IF NOT EXISTS idx_dashboard_backup_jobs_finished
                    ON dashboard_backup_jobs(finished_at DESC)
                    WHERE finished_at IS NOT NULL;
                CREATE INDEX IF NOT EXISTS idx_dashboard_backup_jobs_plan_status
                    ON dashboard_backup_jobs(plan_id, status);
                CREATE UNIQUE INDEX IF NOT EXISTS idx_dashboard_backup_active_plan
                    ON dashboard_backup_jobs(plan_id)
                    WHERE status IN (
                        'queued', 'preparing', 'running', 'verifying',
                        'cancel_requested'
                    );
                """
            )
        os.chmod(self.path, 0o640)

    def quick_check(self) -> bool:
        try:
            with self._connect() as connection:
                result = connection.execute("PRAGMA quick_check").fetchone()
        except sqlite3.Error:
            return False
        return bool(result and result[0] == "ok")

    def reserve(
        self,
        *,
        job_id: str,
        request_id: str,
        plan_id: str,
        display_name: str,
        reason: str | None,
        source_address: str,
        requested_at: datetime,
    ) -> JobReservation:
        with self._connect() as connection:
            connection.execute("BEGIN IMMEDIATE")
            existing = connection.execute(
                "SELECT * FROM dashboard_backup_jobs WHERE request_id = ?",
                (request_id,),
            ).fetchone()
            if existing is not None:
                connection.commit()
                return JobReservation(_row_to_record(existing), duplicate=True)
            busy = connection.execute(
                f"""
                SELECT 1 FROM dashboard_backup_jobs
                WHERE plan_id = ? AND status IN ({_placeholders(ACTIVE_STATES)})
                LIMIT 1
                """,
                (plan_id, *ACTIVE_STATES),
            ).fetchone()
            if busy is not None:
                connection.rollback()
                raise BusyPlanError("backup plan already has an active job")
            try:
                connection.execute(
                    """
                    INSERT INTO dashboard_backup_jobs (
                        job_id, request_id, plan_id, display_name, status,
                        reason, source_address, requested_at, current_phase,
                        verification_state, cancellation_requested
                    ) VALUES (?, ?, ?, ?, 'queued', ?, ?, ?, 'queued', 'pending', 0)
                    """,
                    (
                        job_id,
                        request_id,
                        plan_id,
                        display_name,
                        reason,
                        source_address,
                        requested_at.isoformat(),
                    ),
                )
            except sqlite3.IntegrityError as error:
                connection.rollback()
                raise BusyPlanError("backup plan already has an active job") from error
            row = connection.execute(
                "SELECT * FROM dashboard_backup_jobs WHERE job_id = ?",
                (job_id,),
            ).fetchone()
            connection.commit()
        if row is None:
            raise RuntimeError("backup job reservation was not persisted")
        return JobReservation(_row_to_record(row), duplicate=False)

    def get(self, job_id: str) -> BackupJobResponse | None:
        with self._connect() as connection:
            row = connection.execute(
                "SELECT * FROM dashboard_backup_jobs WHERE job_id = ?",
                (job_id,),
            ).fetchone()
        return _row_to_record(row) if row is not None else None

    def get_by_request_id(self, request_id: str) -> BackupJobResponse | None:
        with self._connect() as connection:
            row = connection.execute(
                "SELECT * FROM dashboard_backup_jobs WHERE request_id = ?",
                (request_id,),
            ).fetchone()
        return _row_to_record(row) if row is not None else None

    def list(self, *, limit: int = 50) -> list[BackupJobResponse]:
        safe_limit = min(max(limit, 1), 200)
        with self._connect() as connection:
            rows = connection.execute(
                """
                SELECT * FROM dashboard_backup_jobs
                ORDER BY requested_at DESC, job_id DESC
                LIMIT ?
                """,
                (safe_limit,),
            ).fetchall()
        return [_row_to_record(row) for row in rows]

    def active_jobs(self) -> list[BackupJobResponse]:
        with self._connect() as connection:
            rows = connection.execute(
                f"""
                SELECT * FROM dashboard_backup_jobs
                WHERE status IN ({_placeholders(ACTIVE_STATES)})
                ORDER BY requested_at
                """,
                ACTIVE_STATES,
            ).fetchall()
        return [_row_to_record(row) for row in rows]

    def running_count(self) -> int:
        with self._connect() as connection:
            row = connection.execute(
                f"""
                SELECT COUNT(*) FROM dashboard_backup_jobs
                WHERE status IN ({_placeholders(ACTIVE_STATES)})
                """,
                ACTIVE_STATES,
            ).fetchone()
        return int(row[0]) if row else 0

    def last_success(self, plan_id: str) -> datetime | None:
        with self._connect() as connection:
            row = connection.execute(
                """
                SELECT finished_at FROM dashboard_backup_jobs
                WHERE plan_id = ? AND status = 'succeeded'
                ORDER BY finished_at DESC LIMIT 1
                """,
                (plan_id,),
            ).fetchone()
        if not row or not row[0]:
            return None
        return datetime.fromisoformat(str(row[0]))

    def mark_preparing(
        self,
        job_id: str,
        *,
        started_at: datetime,
        source_size_estimate: int | None,
    ) -> BackupJobResponse:
        return self._transition(
            job_id,
            expected=("queued",),
            status="preparing",
            values={
                "started_at": started_at.isoformat(),
                "current_phase": "preparing",
                "source_size_estimate": source_size_estimate,
                "progress_percent": 0.0,
            },
        )

    def mark_phase(self, job_id: str, status: BackupJobStatus) -> BackupJobResponse:
        if status == "running":
            expected = ("preparing",)
            phase = "running"
        elif status == "verifying":
            expected = ("running",)
            phase = "verifying"
        else:
            raise ValueError("job phase is invalid")
        return self._transition(
            job_id,
            expected=expected,
            status=status,
            values={"current_phase": phase},
        )

    def update_progress(
        self,
        job_id: str,
        *,
        progress_percent: float | None = None,
        files_examined: int | None = None,
        files_copied: int | None = None,
        bytes_examined: int | None = None,
        bytes_copied: int | None = None,
    ) -> BackupJobResponse:
        values: dict[str, object] = {}
        if progress_percent is not None:
            values["progress_percent"] = min(max(float(progress_percent), 0.0), 100.0)
        for key, value in (
            ("files_examined", files_examined),
            ("files_copied", files_copied),
            ("bytes_examined", bytes_examined),
            ("bytes_copied", bytes_copied),
        ):
            if value is not None:
                values[key] = max(0, int(value))
        if not values:
            record = self.get(job_id)
            if record is None:
                raise JobNotFoundError("backup job was not found")
            return record
        with self._connect() as connection:
            connection.execute("BEGIN IMMEDIATE")
            assignments = ", ".join(f"{key} = ?" for key in values)
            cursor = connection.execute(
                f"""
                UPDATE dashboard_backup_jobs SET {assignments}
                WHERE job_id = ? AND status IN ({_placeholders(ACTIVE_STATES)})
                """,
                (*values.values(), job_id, *ACTIVE_STATES),
            )
            if cursor.rowcount != 1:
                connection.rollback()
                raise JobTransitionError("backup job cannot accept progress")
            row = connection.execute(
                "SELECT * FROM dashboard_backup_jobs WHERE job_id = ?",
                (job_id,),
            ).fetchone()
            connection.commit()
        return _row_to_record(row)

    def reject_queued(
        self,
        job_id: str,
        *,
        finished_at: datetime,
        summary: str,
        error_code: str,
        source_size_estimate: int | None = None,
    ) -> BackupJobResponse:
        return self._transition(
            job_id,
            expected=("queued",),
            status="rejected",
            values={
                "finished_at": finished_at.isoformat(),
                "current_phase": "rejected",
                "result_summary": _sanitize_summary(summary),
                "error_code": _validate_error_code(error_code),
                "source_size_estimate": source_size_estimate,
                "verification_state": "not_applicable",
            },
        )

    def finish(
        self,
        job_id: str,
        *,
        status: BackupJobStatus,
        finished_at: datetime,
        duration_ms: int,
        summary: str,
        error_code: str | None,
        verification_state: str,
        destination_snapshot: str | None,
        manifest_path: str | None,
        progress_percent: float | None = None,
        files_examined: int | None = None,
        files_copied: int | None = None,
        bytes_examined: int | None = None,
        bytes_copied: int | None = None,
    ) -> BackupJobResponse:
        if status not in TERMINAL_STATES:
            raise ValueError("terminal backup status is invalid")
        if verification_state not in {"pending", "passed", "failed", "not_applicable"}:
            raise ValueError("verification state is invalid")
        values: dict[str, object] = {
            "finished_at": finished_at.isoformat(),
            "current_phase": status,
            "duration_ms": max(0, int(duration_ms)),
            "result_summary": _sanitize_summary(summary),
            "error_code": _validate_error_code(error_code) if error_code else None,
            "verification_state": verification_state,
            "destination_snapshot": destination_snapshot,
            "manifest_path": manifest_path,
        }
        if progress_percent is not None:
            values["progress_percent"] = min(max(float(progress_percent), 0.0), 100.0)
        for key, value in (
            ("files_examined", files_examined),
            ("files_copied", files_copied),
            ("bytes_examined", bytes_examined),
            ("bytes_copied", bytes_copied),
        ):
            if value is not None:
                values[key] = max(0, int(value))
        record = self._transition(
            job_id,
            expected=ACTIVE_STATES,
            status=status,
            values=values,
        )
        self.prune()
        return record

    def request_cancel(self, job_id: str, *, requested_at: datetime) -> CancellationResult:
        with self._connect() as connection:
            connection.execute("BEGIN IMMEDIATE")
            row = connection.execute(
                "SELECT * FROM dashboard_backup_jobs WHERE job_id = ?",
                (job_id,),
            ).fetchone()
            if row is None:
                connection.rollback()
                raise JobNotFoundError("backup job was not found")
            status_value = str(row["status"])
            if status_value == "queued":
                connection.execute(
                    """
                    UPDATE dashboard_backup_jobs
                    SET status = 'cancelled', current_phase = 'cancelled',
                        finished_at = ?, result_summary = ?, error_code = ?,
                        verification_state = 'not_applicable',
                        cancellation_requested = 1
                    WHERE job_id = ? AND status = 'queued'
                    """,
                    (
                        requested_at.isoformat(),
                        "Backup cancelled before execution.",
                        "cancelled_by_operator",
                        job_id,
                    ),
                )
                helper_required = False
            elif status_value in {"preparing", "running", "verifying"}:
                connection.execute(
                    """
                    UPDATE dashboard_backup_jobs
                    SET status = 'cancel_requested', current_phase = 'cancel_requested',
                        cancellation_requested = 1
                    WHERE job_id = ? AND status = ?
                    """,
                    (job_id, status_value),
                )
                helper_required = True
            elif status_value == "cancel_requested":
                helper_required = True
            else:
                connection.rollback()
                raise CannotCancelError("backup job is already terminal")
            updated = connection.execute(
                "SELECT * FROM dashboard_backup_jobs WHERE job_id = ?",
                (job_id,),
            ).fetchone()
            connection.commit()
        return CancellationResult(_row_to_record(updated), helper_required=helper_required)

    def recover_interrupted(self) -> int:
        finished_at = _utc_now().isoformat()
        with self._connect() as connection:
            connection.execute("BEGIN IMMEDIATE")
            cursor = connection.execute(
                f"""
                UPDATE dashboard_backup_jobs
                SET status = 'failed', current_phase = 'failed', finished_at = ?,
                    result_summary = 'Backup service restarted before completion.',
                    error_code = 'service_interrupted',
                    verification_state = 'failed'
                WHERE status IN ({_placeholders(ACTIVE_STATES)})
                """,
                (finished_at, *ACTIVE_STATES),
            )
            connection.commit()
        return cursor.rowcount

    def prune(self) -> None:
        cutoff = (_utc_now() - timedelta(days=self.retention_days)).isoformat()
        with self._connect() as connection:
            connection.execute("BEGIN IMMEDIATE")
            connection.execute(
                f"""
                DELETE FROM dashboard_backup_jobs
                WHERE status IN ({_placeholders(TERMINAL_STATES)})
                  AND requested_at < ?
                """,
                (*TERMINAL_STATES, cutoff),
            )
            connection.execute(
                f"""
                DELETE FROM dashboard_backup_jobs
                WHERE status IN ({_placeholders(TERMINAL_STATES)})
                  AND job_id NOT IN (
                    SELECT job_id FROM dashboard_backup_jobs
                    WHERE status IN ({_placeholders(TERMINAL_STATES)})
                    ORDER BY requested_at DESC, job_id DESC
                    LIMIT ?
                  )
                """,
                (*TERMINAL_STATES, *TERMINAL_STATES, self.retention_records),
            )
            connection.commit()

    def _transition(
        self,
        job_id: str,
        *,
        expected: tuple[str, ...],
        status: str,
        values: dict[str, object],
    ) -> BackupJobResponse:
        assignments = ["status = ?", *(f"{column} = ?" for column in values)]
        with self._connect() as connection:
            connection.execute("BEGIN IMMEDIATE")
            cursor = connection.execute(
                f"""
                UPDATE dashboard_backup_jobs
                SET {', '.join(assignments)}
                WHERE job_id = ? AND status IN ({_placeholders(expected)})
                """,
                (status, *values.values(), job_id, *expected),
            )
            if cursor.rowcount != 1:
                connection.rollback()
                raise JobTransitionError("backup job state changed unexpectedly")
            row = connection.execute(
                "SELECT * FROM dashboard_backup_jobs WHERE job_id = ?",
                (job_id,),
            ).fetchone()
            connection.commit()
        return _row_to_record(row)

    def _connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self.path, timeout=10)
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA busy_timeout = 10000")
        connection.execute("PRAGMA journal_mode = WAL")
        connection.execute("PRAGMA synchronous = FULL")
        connection.execute("PRAGMA foreign_keys = ON")
        return connection


def _row_to_record(row: sqlite3.Row) -> BackupJobResponse:
    values = dict(row)
    values.pop("source_address", None)
    values["cancellation_requested"] = bool(values["cancellation_requested"])
    return BackupJobResponse.model_validate(values)


def _placeholders(values: tuple[str, ...]) -> str:
    return ",".join("?" for _ in values)


def _sanitize_summary(value: str) -> str:
    if any(ord(character) < 32 or ord(character) == 127 for character in value):
        raise ValueError("backup summary contains control characters")
    normalized = " ".join(value.split())
    if not normalized or len(normalized) > 300:
        raise ValueError("backup summary is invalid")
    return normalized


def _validate_error_code(value: str) -> str:
    if not ERROR_CODE_PATTERN.fullmatch(value):
        raise ValueError("backup error code is invalid")
    return value


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)
