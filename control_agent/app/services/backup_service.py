from __future__ import annotations

import asyncio
import logging
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from time import monotonic
from uuid import uuid4

from ..core.backup_config import BackupServiceSettings
from ..models.dashboard_backups import (
    BackupAcceptedResponse,
    BackupHealthResponse,
    BackupJobResponse,
    BackupPlanResponse,
    BackupStartRequest,
)
from .backup_executor import (
    BackupAssessment,
    BackupExecutionResult,
    BackupHelper,
    BackupProgress,
    HelperProtocolError,
    HelperUnavailableError,
    SudoBackupHelper,
)
from .backup_registry import BackupPlan, BackupRegistry
from .backup_store import (
    BackupStore,
    BusyPlanError,
    CannotCancelError,
    JobNotFoundError,
    JobTransitionError,
)

logger = logging.getLogger(__name__)


class BackupQueueFullError(RuntimeError):
    pass


@dataclass(frozen=True)
class BackupStartRejected(RuntimeError):
    status_code: int
    error_code: str
    summary: str
    record: BackupJobResponse


class DashboardBackupService:
    def __init__(
        self,
        *,
        settings: BackupServiceSettings,
        registry: BackupRegistry,
        store: BackupStore,
        helper: BackupHelper | None = None,
        version: str,
    ):
        self.settings = settings
        self.registry = registry
        self.store = store
        self.helper: BackupHelper = helper or SudoBackupHelper(settings.helper_path)
        self.version = version
        self.queue: asyncio.Queue[str] = asyncio.Queue(maxsize=settings.queue_size)
        self.workers: list[asyncio.Task[None]] = []
        self._accepted_assessments: dict[str, BackupAssessment] = {}

    async def start(self) -> None:
        self.store.initialize()
        if not self.store.quick_check():
            raise RuntimeError("Dashboard backup database integrity check failed")
        self.store.recover_interrupted()
        self.store.prune()
        first_plan = self.registry.plans[0]
        await self.helper.validate_registry(
            plan_id=first_plan.id,
            fingerprint=self.registry.fingerprint,
        )
        self.workers = [
            asyncio.create_task(self._worker(index), name=f"dashboard-backup-{index}")
            for index in range(self.settings.worker_count)
        ]

    async def stop(self) -> None:
        active = self.store.active_jobs()
        for record in active:
            if record.status in {"preparing", "running", "verifying", "cancel_requested"}:
                try:
                    await self.helper.cancel(
                        plan_id=record.plan_id,
                        job_id=str(record.job_id),
                        fingerprint=self.registry.fingerprint,
                    )
                except Exception:
                    logger.warning("Backup helper cancellation failed during service shutdown")
        for worker in self.workers:
            worker.cancel()
        if self.workers:
            await asyncio.gather(*self.workers, return_exceptions=True)
        self.store.recover_interrupted()
        self.workers = []
        self._accepted_assessments.clear()

    @property
    def workers_healthy(self) -> bool:
        return len(self.workers) == self.settings.worker_count and all(
            not worker.done() for worker in self.workers
        )

    async def accept(
        self,
        *,
        plan: BackupPlan,
        request_body: BackupStartRequest,
        source_address: str,
    ) -> BackupAcceptedResponse:
        request_id = str(request_body.request_id)
        existing = self.store.get_by_request_id(request_id)
        if existing is not None:
            return _accepted(existing, duplicate=True)
        if self.queue.full():
            raise BackupQueueFullError("backup queue is full")

        job_id = str(uuid4())
        try:
            reservation = self.store.reserve(
                job_id=job_id,
                request_id=request_id,
                plan_id=plan.id,
                display_name=plan.display_name,
                reason=request_body.reason,
                source_address=source_address,
                requested_at=_utc_now(),
            )
        except BusyPlanError:
            raise
        if reservation.duplicate:
            return _accepted(reservation.record, duplicate=True)

        if not plan.enabled:
            disabled_summary = plan.disabled_reason or "Backup plan is disabled by the root-owned registry."
            rejected = self.store.reject_queued(
                job_id,
                finished_at=_utc_now(),
                summary=disabled_summary,
                error_code="plan_disabled",
                source_size_estimate=plan.estimated_size_bytes,
            )
            raise BackupStartRejected(
                status_code=409,
                error_code="plan_disabled",
                summary=disabled_summary,
                record=rejected,
            )

        try:
            assessment = await self.helper.assess(
                plan=plan,
                job_id=job_id,
                fingerprint=self.registry.fingerprint,
                operation="preflight",
            )
        except (HelperProtocolError, HelperUnavailableError):
            rejected = self.store.reject_queued(
                job_id,
                finished_at=_utc_now(),
                summary="Backup safety preflight was unavailable.",
                error_code="preflight_unavailable",
                source_size_estimate=plan.estimated_size_bytes,
            )
            raise BackupStartRejected(
                status_code=503,
                error_code="preflight_unavailable",
                summary="Backup safety preflight is unavailable.",
                record=rejected,
            )

        if not assessment.allowed:
            error_code = assessment.blocking_code or "unsafe_to_start"
            summary = assessment.blocking_reason or "Backup safety preflight rejected the job."
            rejected = self.store.reject_queued(
                job_id,
                finished_at=_utc_now(),
                summary=summary,
                error_code=error_code,
                source_size_estimate=assessment.source_size_estimate,
            )
            raise BackupStartRejected(
                status_code=507 if error_code == "insufficient_capacity" else 409,
                error_code=error_code,
                summary=summary,
                record=rejected,
            )

        self._accepted_assessments[job_id] = assessment
        try:
            self.queue.put_nowait(job_id)
        except asyncio.QueueFull as error:
            self._accepted_assessments.pop(job_id, None)
            rejected = self.store.reject_queued(
                job_id,
                finished_at=_utc_now(),
                summary="Backup queue became unavailable before execution.",
                error_code="queue_full",
                source_size_estimate=assessment.source_size_estimate,
            )
            raise BackupStartRejected(
                status_code=429,
                error_code="queue_full",
                summary="Backup queue is full.",
                record=rejected,
            ) from error
        return _accepted(reservation.record, duplicate=False)

    async def cancel(self, job_id: str) -> BackupJobResponse:
        result = self.store.request_cancel(job_id, requested_at=_utc_now())
        if result.helper_required:
            try:
                await self.helper.cancel(
                    plan_id=result.record.plan_id,
                    job_id=job_id,
                    fingerprint=self.registry.fingerprint,
                )
            except (HelperProtocolError, HelperUnavailableError):
                logger.warning("Backup cancellation signal could not be confirmed")
        return self.store.get(job_id) or result.record

    async def describe_plan(self, plan: BackupPlan) -> BackupPlanResponse:
        assessment: BackupAssessment | None = None
        try:
            assessment = await self.helper.assess(
                plan=plan,
                job_id=str(uuid4()),
                fingerprint=self.registry.fingerprint,
                operation="assess",
            )
        except (HelperProtocolError, HelperUnavailableError):
            pass
        if not plan.enabled:
            allowed = False
            blocking_reason = plan.disabled_reason or "Disabled by the root-owned backup registry."
        elif assessment is None:
            allowed = False
            blocking_reason = "Backup safety assessment is unavailable."
        else:
            allowed = assessment.allowed
            blocking_reason = assessment.blocking_reason
        return BackupPlanResponse(
            id=plan.id,
            display_name=plan.display_name,
            description=plan.description,
            enabled=plan.enabled,
            estimated_source_size=(
                assessment.source_size_estimate if assessment else plan.estimated_size_bytes
            ),
            last_successful_run=self.store.last_success(plan.id),
            allowed_to_start_now=allowed,
            blocking_reason=blocking_reason,
            destination_free_bytes=(
                assessment.destination_free_bytes if assessment else None
            ),
            retention_policy=(
                "Manual snapshot retention; no automatic snapshot deletion; "
                f"retain at least {plan.retention.retain_at_least}."
            ),
            confirmation_level=plan.confirmation_level,
        )

    async def health(self) -> BackupHealthResponse:
        assessment: BackupAssessment | None = None
        try:
            assessment = await self.helper.assess(
                plan=self.registry.plans[0],
                job_id=str(uuid4()),
                fingerprint=self.registry.fingerprint,
                operation="assess",
            )
        except (HelperProtocolError, HelperUnavailableError):
            pass
        database_healthy = self.store.quick_check()
        worker_healthy = self.workers_healthy
        mounted = assessment.cold_storage_mounted if assessment else False
        writable = assessment.cold_storage_writable if assessment else False
        raid_healthy = assessment.raid_healthy if assessment else False
        healthy = database_healthy and worker_healthy and mounted and writable and raid_healthy
        return BackupHealthResponse(
            status="ok" if healthy else "degraded",
            version=self.version,
            registry_loaded=True,
            plan_count=len(self.registry.plans),
            database_healthy=database_healthy,
            worker_healthy=worker_healthy,
            cold_storage_mounted=mounted,
            cold_storage_writable=writable,
            raid_healthy=raid_healthy,
            free_bytes=assessment.destination_free_bytes if assessment else None,
            running_job_count=self.store.running_count(),
            observation_timestamp=_utc_now(),
        )

    async def wait_until_idle(self) -> None:
        await self.queue.join()

    async def _worker(self, worker_index: int) -> None:
        while True:
            job_id = await self.queue.get()
            try:
                await self._execute(job_id)
            except asyncio.CancelledError:
                raise
            except Exception as error:
                logger.error(
                    "Dashboard backup worker %s failed (%s)",
                    worker_index,
                    type(error).__name__,
                )
            finally:
                self._accepted_assessments.pop(job_id, None)
                self.queue.task_done()

    async def _execute(self, job_id: str) -> None:
        record = self.store.get(job_id)
        if record is None or record.status != "queued":
            return
        plan = self.registry.get_plan(record.plan_id)
        if plan is None or not plan.enabled:
            self.store.reject_queued(
                job_id,
                finished_at=_utc_now(),
                summary="Backup plan is no longer available.",
                error_code="plan_unavailable",
                source_size_estimate=record.source_size_estimate,
            )
            return
        assessment = self._accepted_assessments.get(job_id)
        self.store.mark_preparing(
            job_id,
            started_at=_utc_now(),
            source_size_estimate=(
                assessment.source_size_estimate
                if assessment is not None
                else plan.estimated_size_bytes
            ),
        )
        started = monotonic()

        async def on_progress(progress: BackupProgress) -> None:
            current = self.store.get(job_id)
            if current is None or current.status in {"cancelled", "failed", "timed_out"}:
                return
            try:
                if progress.phase == "running" and current.status == "preparing":
                    self.store.mark_phase(job_id, "running")
                elif progress.phase == "verifying" and current.status == "running":
                    self.store.mark_phase(job_id, "verifying")
                self.store.update_progress(
                    job_id,
                    progress_percent=progress.progress_percent,
                    files_examined=progress.files_examined,
                    files_copied=progress.files_copied,
                    bytes_examined=progress.bytes_examined,
                    bytes_copied=progress.bytes_copied,
                )
            except JobTransitionError:
                return

        try:
            result = await self.helper.execute(
                plan=plan,
                job_id=job_id,
                fingerprint=self.registry.fingerprint,
                on_progress=on_progress,
            )
        except asyncio.CancelledError:
            raise
        except HelperProtocolError:
            result = _failed_result(
                "Backup helper returned an invalid response.",
                "helper_protocol_error",
            )
        except HelperUnavailableError:
            result = _failed_result(
                "Backup helper became unavailable.",
                "helper_unavailable",
            )
        except Exception as error:
            logger.error("Backup helper failed (%s)", type(error).__name__)
            result = _failed_result(
                "Backup execution failed at the privilege boundary.",
                "helper_unavailable",
            )

        duration_ms = round((monotonic() - started) * 1000)
        try:
            self.store.finish(
                job_id,
                status=result.status,  # type: ignore[arg-type]
                finished_at=_utc_now(),
                duration_ms=duration_ms,
                summary=result.summary,
                error_code=result.error_code,
                verification_state=result.verification_state,
                destination_snapshot=result.destination_snapshot,
                manifest_path=result.manifest_path,
                progress_percent=100.0 if result.status == "succeeded" else None,
                files_examined=result.files_examined,
                files_copied=result.files_copied,
                bytes_examined=result.bytes_examined,
                bytes_copied=result.bytes_copied,
            )
        except JobTransitionError:
            logger.warning("Backup completion state was already changed")


def _accepted(record: BackupJobResponse, *, duplicate: bool) -> BackupAcceptedResponse:
    return BackupAcceptedResponse(
        job=record,
        duplicate=duplicate,
        polling_location=f"/jobs/{record.job_id}",
    )


def _failed_result(summary: str, error_code: str) -> BackupExecutionResult:
    return BackupExecutionResult(
        status="failed",
        summary=summary,
        error_code=error_code,
        verification_state="failed",
        destination_snapshot=None,
        manifest_path=None,
        files_examined=None,
        files_copied=None,
        bytes_examined=None,
        bytes_copied=None,
    )


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)
