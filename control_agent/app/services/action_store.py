from __future__ import annotations

import os
import sqlite3
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path

from ..models.dashboard_actions import ActionRecordResponse

ACTIVE_STATES = ("queued", "running")
TERMINAL_STATES = ("succeeded", "failed", "rejected", "timed_out")


class BusyTargetError(RuntimeError):
    pass


class StateTransitionError(RuntimeError):
    pass


@dataclass(frozen=True)
class ReservationResult:
    record: ActionRecordResponse
    duplicate: bool


class ActionStore:
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
        with self._connect() as connection:
            connection.executescript(
                """
                CREATE TABLE IF NOT EXISTS dashboard_actions (
                    action_id TEXT PRIMARY KEY,
                    request_id TEXT NOT NULL UNIQUE,
                    caller TEXT NOT NULL,
                    source_address TEXT NOT NULL,
                    target_id TEXT NOT NULL,
                    display_name TEXT NOT NULL,
                    action TEXT NOT NULL,
                    status TEXT NOT NULL,
                    reason TEXT,
                    requested_at TEXT NOT NULL,
                    started_at TEXT,
                    finished_at TEXT,
                    result_summary TEXT,
                    error_code TEXT,
                    duration_ms INTEGER,
                    previous_state TEXT,
                    resulting_state TEXT,
                    CHECK (status IN (
                        'queued', 'running', 'succeeded', 'failed', 'rejected', 'timed_out'
                    ))
                );
                CREATE INDEX IF NOT EXISTS idx_dashboard_actions_requested_at
                    ON dashboard_actions(requested_at DESC);
                CREATE INDEX IF NOT EXISTS idx_dashboard_actions_target_status
                    ON dashboard_actions(target_id, status);
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

    def recover_interrupted(self) -> int:
        finished_at = _utc_now().isoformat()
        with self._connect() as connection:
            connection.execute("BEGIN IMMEDIATE")
            cursor = connection.execute(
                """
                UPDATE dashboard_actions
                SET status = 'failed', finished_at = ?,
                    result_summary = 'Action service restarted before completion.',
                    error_code = 'action_service_restarted'
                WHERE status IN ('queued', 'running')
                """,
                (finished_at,),
            )
            connection.commit()
        return cursor.rowcount

    def reserve(
        self,
        *,
        action_id: str,
        request_id: str,
        caller: str,
        source_address: str,
        target_id: str,
        display_name: str,
        action: str,
        reason: str | None,
        requested_at: datetime,
    ) -> ReservationResult:
        with self._connect() as connection:
            connection.execute("BEGIN IMMEDIATE")
            existing = connection.execute(
                "SELECT * FROM dashboard_actions WHERE request_id = ?",
                (request_id,),
            ).fetchone()
            if existing is not None:
                connection.commit()
                return ReservationResult(_row_to_record(existing), duplicate=True)

            busy = connection.execute(
                """
                SELECT 1 FROM dashboard_actions
                WHERE target_id = ? AND status IN ('queued', 'running')
                LIMIT 1
                """,
                (target_id,),
            ).fetchone()
            if busy is not None:
                connection.rollback()
                raise BusyTargetError("target already has an active action")

            connection.execute(
                """
                INSERT INTO dashboard_actions (
                    action_id, request_id, caller, source_address, target_id,
                    display_name, action, status, reason, requested_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, 'queued', ?, ?)
                """,
                (
                    action_id,
                    request_id,
                    caller,
                    source_address,
                    target_id,
                    display_name,
                    action,
                    reason,
                    requested_at.isoformat(),
                ),
            )
            row = connection.execute(
                "SELECT * FROM dashboard_actions WHERE action_id = ?",
                (action_id,),
            ).fetchone()
            connection.commit()
        if row is None:  # pragma: no cover - guarded by the transaction
            raise RuntimeError("action reservation was not persisted")
        return ReservationResult(_row_to_record(row), duplicate=False)

    def mark_running(
        self,
        action_id: str,
        *,
        started_at: datetime,
    ) -> ActionRecordResponse:
        return self._transition(
            action_id,
            expected_status="queued",
            status="running",
            values={"started_at": started_at.isoformat()},
        )

    def finish(
        self,
        action_id: str,
        *,
        status: str,
        finished_at: datetime,
        result_summary: str,
        error_code: str | None,
        duration_ms: int,
        previous_state: str | None,
        resulting_state: str | None,
    ) -> ActionRecordResponse:
        if status not in TERMINAL_STATES:
            raise ValueError("action finish state is invalid")
        record = self._transition(
            action_id,
            expected_status="running",
            status=status,
            values={
                "finished_at": finished_at.isoformat(),
                "result_summary": result_summary,
                "error_code": error_code,
                "duration_ms": max(0, duration_ms),
                "previous_state": previous_state,
                "resulting_state": resulting_state,
            },
        )
        self.prune()
        return record

    def get(self, action_id: str) -> ActionRecordResponse | None:
        with self._connect() as connection:
            row = connection.execute(
                "SELECT * FROM dashboard_actions WHERE action_id = ?",
                (action_id,),
            ).fetchone()
        return _row_to_record(row) if row is not None else None

    def get_by_request_id(self, request_id: str) -> ActionRecordResponse | None:
        with self._connect() as connection:
            row = connection.execute(
                "SELECT * FROM dashboard_actions WHERE request_id = ?",
                (request_id,),
            ).fetchone()
        return _row_to_record(row) if row is not None else None

    def list(self, *, limit: int = 50) -> list[ActionRecordResponse]:
        safe_limit = min(max(limit, 1), 200)
        with self._connect() as connection:
            rows = connection.execute(
                """
                SELECT * FROM dashboard_actions
                ORDER BY requested_at DESC, action_id DESC
                LIMIT ?
                """,
                (safe_limit,),
            ).fetchall()
        return [_row_to_record(row) for row in rows]

    def busy_targets(self) -> set[str]:
        with self._connect() as connection:
            rows = connection.execute(
                """
                SELECT DISTINCT target_id FROM dashboard_actions
                WHERE status IN ('queued', 'running')
                """
            ).fetchall()
        return {str(row[0]) for row in rows}

    def prune(self) -> None:
        cutoff = (_utc_now() - timedelta(days=self.retention_days)).isoformat()
        placeholders = ",".join("?" for _ in TERMINAL_STATES)
        with self._connect() as connection:
            connection.execute("BEGIN IMMEDIATE")
            connection.execute(
                f"""
                DELETE FROM dashboard_actions
                WHERE status IN ({placeholders}) AND requested_at < ?
                """,
                (*TERMINAL_STATES, cutoff),
            )
            connection.execute(
                f"""
                DELETE FROM dashboard_actions
                WHERE status IN ({placeholders})
                  AND action_id NOT IN (
                    SELECT action_id FROM dashboard_actions
                    WHERE status IN ({placeholders})
                    ORDER BY requested_at DESC, action_id DESC
                    LIMIT ?
                  )
                """,
                (*TERMINAL_STATES, *TERMINAL_STATES, self.retention_records),
            )
            connection.commit()

    def _transition(
        self,
        action_id: str,
        *,
        expected_status: str,
        status: str,
        values: dict[str, object],
    ) -> ActionRecordResponse:
        assignments = ["status = ?", *(f"{column} = ?" for column in values)]
        arguments = [status, *values.values(), action_id, expected_status]
        with self._connect() as connection:
            connection.execute("BEGIN IMMEDIATE")
            cursor = connection.execute(
                f"""
                UPDATE dashboard_actions SET {', '.join(assignments)}
                WHERE action_id = ? AND status = ?
                """,
                arguments,
            )
            if cursor.rowcount != 1:
                connection.rollback()
                raise StateTransitionError("action state changed unexpectedly")
            row = connection.execute(
                "SELECT * FROM dashboard_actions WHERE action_id = ?",
                (action_id,),
            ).fetchone()
            connection.commit()
        if row is None:  # pragma: no cover - guarded by the update
            raise StateTransitionError("action disappeared during transition")
        return _row_to_record(row)

    def _connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self.path, timeout=5)
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA busy_timeout = 5000")
        connection.execute("PRAGMA journal_mode = WAL")
        connection.execute("PRAGMA synchronous = FULL")
        return connection


def _row_to_record(row: sqlite3.Row) -> ActionRecordResponse:
    return ActionRecordResponse.model_validate(dict(row))


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)
