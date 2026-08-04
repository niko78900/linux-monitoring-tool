from __future__ import annotations

import asyncio
import logging
from collections.abc import Callable
from dataclasses import dataclass
from datetime import datetime, timezone

from .backup_executor import (
    BackupAssessment,
    BackupHelper,
    HelperProtocolError,
    HelperUnavailableError,
)
from .backup_registry import BackupPlan

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class AssessmentView:
    assessment: BackupAssessment | None
    observed_at: datetime | None
    age_seconds: float | None
    stale: bool
    in_progress: bool
    estimate_error: str | None
    refresh_due: bool


@dataclass
class _AssessmentEntry:
    assessment: BackupAssessment | None = None
    observed_at: datetime | None = None
    last_attempt_at: datetime | None = None
    estimate_error: str | None = None


class BackupAssessmentCache:
    """Bounded, observational cache for expensive plan assessments.

    Cached assessments are used only to describe plans. Backup acceptance
    continues to call the privileged helper with ``operation=preflight``.
    """

    def __init__(
        self,
        *,
        helper: BackupHelper,
        registry_fingerprint: str,
        refresh_seconds: int,
        max_age_seconds: int,
        timeout_seconds: int,
        concurrency: int,
        can_refresh: Callable[[], bool],
    ) -> None:
        self.helper = helper
        self.registry_fingerprint = registry_fingerprint
        self.refresh_seconds = refresh_seconds
        self.max_age_seconds = max_age_seconds
        self.timeout_seconds = timeout_seconds
        self.concurrency = concurrency
        self.can_refresh = can_refresh
        self._entries: dict[str, _AssessmentEntry] = {}
        self._tasks: dict[str, asyncio.Task[None]] = {}
        self._locks: dict[str, asyncio.Lock] = {}
        self._semaphore = asyncio.Semaphore(concurrency)
        self._running_count = 0
        self._closed = False

    @property
    def healthy(self) -> bool:
        return not self._closed and self.active_count <= self.concurrency

    @property
    def active_count(self) -> int:
        return self._running_count

    def view(self, plan_id: str, *, now: datetime | None = None) -> AssessmentView:
        current = now or _utc_now()
        entry = self._entries.get(plan_id)
        task = self._tasks.get(plan_id)
        in_progress = bool(task is not None and not task.done())
        if entry is None:
            return AssessmentView(
                assessment=None,
                observed_at=None,
                age_seconds=None,
                stale=True,
                in_progress=in_progress,
                estimate_error=None,
                refresh_due=True,
            )

        age_seconds = (
            max(0.0, (current - entry.observed_at).total_seconds())
            if entry.observed_at is not None
            else None
        )
        stale = (
            entry.assessment is None
            or age_seconds is None
            or age_seconds > self.max_age_seconds
            or entry.estimate_error is not None
        )
        if entry.estimate_error is not None and entry.last_attempt_at is not None:
            retry_age = max(0.0, (current - entry.last_attempt_at).total_seconds())
            refresh_due = retry_age >= min(60, self.refresh_seconds)
        else:
            refresh_due = age_seconds is None or age_seconds >= self.refresh_seconds
        return AssessmentView(
            assessment=entry.assessment,
            observed_at=entry.observed_at,
            age_seconds=age_seconds,
            stale=stale,
            in_progress=in_progress,
            estimate_error=entry.estimate_error,
            refresh_due=refresh_due,
        )

    def request_refresh(
        self,
        plan: BackupPlan,
        *,
        force: bool = False,
    ) -> asyncio.Task[None] | None:
        if self._closed:
            return None
        existing = self._tasks.get(plan.id)
        if existing is not None and not existing.done():
            return existing
        if not force and not self.view(plan.id).refresh_due:
            return None
        task = asyncio.create_task(
            self._refresh(plan, force=force),
            name=f"backup-assessment-{plan.id}",
        )
        self._tasks[plan.id] = task
        task.add_done_callback(lambda completed: self._remove_task(plan.id, completed))
        return task

    async def wait_for_refresh(
        self,
        plan: BackupPlan,
        *,
        force: bool,
        wait_seconds: int,
    ) -> None:
        task = self.request_refresh(plan, force=force)
        if task is None or wait_seconds <= 0:
            return
        try:
            await asyncio.wait_for(asyncio.shield(task), timeout=wait_seconds)
        except asyncio.TimeoutError:
            # The refresh remains bounded by its own helper timeout and keeps
            # running for other callers. This request returns cached metadata.
            return

    def record_success(
        self,
        plan_id: str,
        assessment: BackupAssessment,
        *,
        observed_at: datetime | None = None,
    ) -> None:
        current = observed_at or _utc_now()
        self._entries[plan_id] = _AssessmentEntry(
            assessment=assessment,
            observed_at=current,
            last_attempt_at=current,
            estimate_error=None,
        )

    def record_failure(
        self,
        plan_id: str,
        error_code: str,
        *,
        attempted_at: datetime | None = None,
    ) -> None:
        current = attempted_at or _utc_now()
        entry = self._entries.setdefault(plan_id, _AssessmentEntry())
        entry.last_attempt_at = current
        entry.estimate_error = error_code

    async def stop(self) -> None:
        self._closed = True
        await self.pause_for_backup()
        self._tasks.clear()

    async def pause_for_backup(self) -> None:
        """Yield assessment capacity before a real backup preflight starts."""
        tasks = [task for task in self._tasks.values() if not task.done()]
        for task in tasks:
            task.cancel()
        if tasks:
            await asyncio.gather(*tasks, return_exceptions=True)

    async def _refresh(self, plan: BackupPlan, *, force: bool) -> None:
        lock = self._locks.setdefault(plan.id, asyncio.Lock())
        async with lock:
            if not force and not self.view(plan.id).refresh_due:
                return
            while not self.can_refresh():
                await asyncio.sleep(0.1)
            async with self._semaphore:
                while not self.can_refresh():
                    await asyncio.sleep(0.1)
                self._running_count += 1
                try:
                    try:
                        assessment = await asyncio.wait_for(
                            self.helper.assess(
                                plan=plan,
                                job_id=_assessment_job_id(plan.id),
                                fingerprint=self.registry_fingerprint,
                                operation="assess",
                            ),
                            timeout=self.timeout_seconds,
                        )
                    except asyncio.TimeoutError:
                        self.record_failure(plan.id, "assessment_timeout")
                    except (HelperProtocolError, HelperUnavailableError):
                        self.record_failure(plan.id, "assessment_unavailable")
                    except asyncio.CancelledError:
                        raise
                    except Exception as error:
                        logger.warning(
                            "Backup assessment failed for %s (%s)",
                            plan.id,
                            type(error).__name__,
                        )
                        self.record_failure(plan.id, "assessment_failed")
                    else:
                        self.record_success(plan.id, assessment)
                finally:
                    self._running_count -= 1

    def _remove_task(self, plan_id: str, completed: asyncio.Task[None]) -> None:
        if self._tasks.get(plan_id) is completed:
            self._tasks.pop(plan_id, None)
        if completed.cancelled():
            return
        try:
            completed.result()
        except Exception as error:
            logger.warning(
                "Backup assessment task failed for %s (%s)",
                plan_id,
                type(error).__name__,
            )


def _assessment_job_id(plan_id: str) -> str:
    # Helper assessment operations validate UUID syntax but do not persist or
    # create a snapshot. A deterministic UUID keeps this metadata-only path
    # independent from backup job history.
    import uuid

    return str(uuid.uuid5(uuid.NAMESPACE_URL, f"linux-monitor-backup-assessment:{plan_id}"))


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)
