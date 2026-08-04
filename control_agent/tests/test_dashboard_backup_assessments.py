from __future__ import annotations

import asyncio
import sys
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path
from types import SimpleNamespace
from uuid import UUID

import pytest

from app.services.backup_assessments import BackupAssessmentCache
from app.services.backup_executor import (
    BackupAssessment,
    HelperUnavailableError,
    SudoBackupHelper,
)


ASSESSMENT = BackupAssessment(
    allowed=True,
    blocking_code=None,
    blocking_reason=None,
    source_size_estimate=1024,
    destination_free_bytes=10_000,
    required_bytes=2048,
    cold_storage_mounted=True,
    cold_storage_writable=True,
    raid_healthy=True,
)


class ControlledHelper:
    def __init__(self) -> None:
        self.calls: list[str] = []
        self.active = 0
        self.maximum_active = 0
        self.gates: dict[str, asyncio.Event] = {}
        self.failures: dict[str, Exception] = {}
        self.delays: dict[str, float] = {}

    async def assess(self, *, plan, job_id: str, fingerprint: str, operation: str = "assess"):
        assert operation == "assess"
        UUID(job_id)
        self.calls.append(plan.id)
        self.active += 1
        self.maximum_active = max(self.maximum_active, self.active)
        try:
            delay = self.delays.get(plan.id, 0)
            if delay:
                await asyncio.sleep(delay)
            gate = self.gates.get(plan.id)
            if gate is not None:
                await gate.wait()
            failure = self.failures.get(plan.id)
            if failure is not None:
                raise failure
            return ASSESSMENT
        finally:
            self.active -= 1


def _plan(plan_id: str):
    return SimpleNamespace(id=plan_id)


def _cache(
    helper: ControlledHelper,
    *,
    concurrency: int = 2,
    timeout: float = 1,
    can_refresh=lambda: True,
) -> BackupAssessmentCache:
    return BackupAssessmentCache(
        helper=helper,
        registry_fingerprint="a" * 64,
        refresh_seconds=60,
        max_age_seconds=120,
        timeout_seconds=timeout,
        concurrency=concurrency,
        can_refresh=can_refresh,
    )


def test_empty_fresh_stale_and_restart_cache_states() -> None:
    async def scenario() -> None:
        now = datetime.now(timezone.utc)
        cache = _cache(ControlledHelper())
        empty = cache.view("database", now=now)
        assert empty.assessment is None
        assert empty.stale is True
        assert empty.refresh_due is True

        cache.record_success("database", ASSESSMENT, observed_at=now)
        fresh = cache.view("database", now=now + timedelta(seconds=30))
        assert fresh.assessment == ASSESSMENT
        assert fresh.stale is False
        assert fresh.refresh_due is False

        stale = cache.view("database", now=now + timedelta(seconds=121))
        assert stale.assessment == ASSESSMENT
        assert stale.stale is True
        assert stale.refresh_due is True

        restarted = _cache(ControlledHelper())
        assert restarted.view("database").assessment is None
        await cache.stop()
        await restarted.stop()

    asyncio.run(scenario())


def test_refresh_is_deduplicated_and_locked_per_plan() -> None:
    async def scenario() -> None:
        helper = ControlledHelper()
        helper.gates["database"] = asyncio.Event()
        cache = _cache(helper)
        first = cache.request_refresh(_plan("database"))
        second = cache.request_refresh(_plan("database"), force=True)
        assert first is second
        await asyncio.sleep(0)
        assert helper.calls == ["database"]
        assert cache.view("database").in_progress is True
        helper.gates["database"].set()
        assert first is not None
        await first
        assert cache.view("database").assessment == ASSESSMENT
        await cache.stop()

    asyncio.run(scenario())


def test_global_assessment_concurrency_is_bounded() -> None:
    async def scenario() -> None:
        helper = ControlledHelper()
        for plan_id in ("one", "two", "three"):
            helper.gates[plan_id] = asyncio.Event()
        cache = _cache(helper, concurrency=2)
        tasks = [cache.request_refresh(_plan(plan_id)) for plan_id in helper.gates]
        await asyncio.sleep(0.02)
        assert helper.maximum_active == 2
        assert helper.active == 2
        for gate in helper.gates.values():
            gate.set()
        await asyncio.gather(*(task for task in tasks if task is not None))
        assert helper.maximum_active == 2
        await cache.stop()

    asyncio.run(scenario())


def test_timeout_failure_and_last_known_good_are_safe() -> None:
    async def scenario() -> None:
        helper = ControlledHelper()
        helper.delays["slow"] = 0.1
        cache = _cache(helper, timeout=0.01)
        task = cache.request_refresh(_plan("slow"))
        assert task is not None
        await task
        timed_out = cache.view("slow")
        assert timed_out.assessment is None
        assert timed_out.estimate_error == "assessment_timeout"
        assert timed_out.stale is True

        cache.record_success("failed", ASSESSMENT)
        helper.failures["failed"] = HelperUnavailableError("private helper output")
        task = cache.request_refresh(_plan("failed"), force=True)
        assert task is not None
        await task
        failed = cache.view("failed")
        assert failed.assessment == ASSESSMENT
        assert failed.estimate_error == "assessment_unavailable"
        assert failed.stale is True
        assert "private" not in failed.estimate_error
        await cache.stop()

    asyncio.run(scenario())


def test_slow_warm_assessment_does_not_block_other_plan_reads() -> None:
    async def scenario() -> None:
        helper = ControlledHelper()
        helper.gates["warm-storage"] = asyncio.Event()
        cache = _cache(helper, concurrency=2)
        warm_task = cache.request_refresh(_plan("warm-storage"))
        small_task = cache.request_refresh(_plan("database"))
        assert small_task is not None
        await asyncio.wait_for(small_task, timeout=0.2)
        assert cache.view("database").assessment == ASSESSMENT
        started = time.monotonic()
        warm_view = cache.view("warm-storage")
        assert time.monotonic() - started < 0.05
        assert warm_view.in_progress is True
        helper.gates["warm-storage"].set()
        assert warm_task is not None
        await warm_task
        await cache.stop()

    asyncio.run(scenario())


def test_backup_priority_pauses_workers_and_shutdown_cancels_them() -> None:
    async def scenario() -> None:
        backup_active = False
        helper = ControlledHelper()
        helper.gates["warm-storage"] = asyncio.Event()
        cache = _cache(helper, can_refresh=lambda: not backup_active)
        task = cache.request_refresh(_plan("warm-storage"))
        await asyncio.sleep(0)
        assert helper.active == 1
        backup_active = True
        await cache.pause_for_backup()
        assert task is not None and task.cancelled()
        assert helper.active == 0

        queued = cache.request_refresh(_plan("database"))
        await asyncio.sleep(0.02)
        assert helper.calls == ["warm-storage"]
        backup_active = False
        assert queued is not None
        await asyncio.wait_for(queued, timeout=0.2)

        helper.gates["another"] = asyncio.Event()
        shutdown_task = cache.request_refresh(_plan("another"))
        await asyncio.sleep(0)
        await cache.stop()
        assert shutdown_task is not None and shutdown_task.cancelled()
        assert helper.active == 0

    asyncio.run(scenario())


def test_cancelled_helper_is_reaped_with_its_process_group(tmp_path: Path) -> None:
    async def scenario() -> None:
        child_pid_path = tmp_path / "child.pid"
        processes: list[asyncio.subprocess.Process] = []
        helper = SudoBackupHelper(Path("/unused"))

        async def spawn(_payload: bytes) -> asyncio.subprocess.Process:
            script = (
                "import pathlib, subprocess, sys, time; "
                "child=subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(60)']); "
                f"pathlib.Path({str(child_pid_path)!r}).write_text(str(child.pid)); "
                "time.sleep(60)"
            )
            process = await asyncio.create_subprocess_exec(
                sys.executable,
                "-c",
                script,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                start_new_session=True,
            )
            processes.append(process)
            return process

        helper._spawn = spawn  # type: ignore[method-assign]
        request = asyncio.create_task(
            helper._single_response(
                operation="assess",
                plan_id="database",
                job_id="00000000-0000-0000-0000-000000000000",
                timeout_seconds=60,
            )
        )
        deadline = time.monotonic() + 2
        while not child_pid_path.exists() and time.monotonic() < deadline:
            await asyncio.sleep(0.01)
        assert child_pid_path.exists()
        child_pid = int(child_pid_path.read_text(encoding="ascii"))
        request.cancel()
        with pytest.raises(asyncio.CancelledError):
            await request
        assert processes[0].returncode is not None

        deadline = time.monotonic() + 2
        while Path(f"/proc/{child_pid}").exists() and time.monotonic() < deadline:
            await asyncio.sleep(0.01)
        assert not Path(f"/proc/{child_pid}").exists()

    asyncio.run(scenario())
