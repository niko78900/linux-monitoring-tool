from __future__ import annotations

import asyncio
import logging
from datetime import datetime, timezone
from time import monotonic
from typing import Protocol
from uuid import UUID, uuid4

from ..core.action_config import ActionServiceSettings
from ..models.dashboard_actions import (
    ActionAcceptedResponse,
    ActionRecordResponse,
    ActionRequest,
    ServiceAction,
)
from .action_executor import HelperExecutionResult, HelperProtocolError, SudoActionHelper
from .action_registry import ActionRegistry, ManagedActionService, WakeTarget
from .action_store import ActionStore, BusyTargetError, StateTransitionError

logger = logging.getLogger(__name__)


class HelperRunner(Protocol):
    async def execute(
        self,
        record: ActionRecordResponse,
        *,
        timeout_seconds: int,
    ) -> HelperExecutionResult: ...


class ActionQueueFullError(RuntimeError):
    pass


class DashboardActionService:
    def __init__(
        self,
        *,
        settings: ActionServiceSettings,
        registry: ActionRegistry,
        store: ActionStore,
        helper: HelperRunner | None = None,
    ):
        self.settings = settings
        self.registry = registry
        self.store = store
        self.helper: HelperRunner = helper or SudoActionHelper(settings.helper_path)
        self.queue: asyncio.Queue[str] = asyncio.Queue(maxsize=settings.queue_size)
        self.workers: list[asyncio.Task[None]] = []

    async def start(self) -> None:
        self.store.initialize()
        self.store.recover_interrupted()
        self.store.prune()
        self.workers = [
            asyncio.create_task(self._worker(index), name=f"dashboard-action-{index}")
            for index in range(self.settings.worker_count)
        ]

    async def stop(self) -> None:
        for worker in self.workers:
            worker.cancel()
        if self.workers:
            await asyncio.gather(*self.workers, return_exceptions=True)
        self.store.recover_interrupted()
        self.workers = []

    @property
    def workers_healthy(self) -> bool:
        return len(self.workers) == self.settings.worker_count and all(
            not worker.done() for worker in self.workers
        )

    def accept_service_action(
        self,
        *,
        service: ManagedActionService,
        action: ServiceAction,
        action_request: ActionRequest,
        source_address: str,
    ) -> ActionAcceptedResponse:
        return self._accept(
            target_id=service.id,
            display_name=service.name,
            action=action,
            action_request=action_request,
            source_address=source_address,
        )

    def accept_wake_action(
        self,
        *,
        target: WakeTarget,
        action_request: ActionRequest,
        source_address: str,
    ) -> ActionAcceptedResponse:
        return self._accept(
            target_id=target.id,
            display_name=target.name,
            action="wake",
            action_request=action_request,
            source_address=source_address,
        )

    def _accept(
        self,
        *,
        target_id: str,
        display_name: str,
        action: str,
        action_request: ActionRequest,
        source_address: str,
    ) -> ActionAcceptedResponse:
        if self.queue.full():
            raise ActionQueueFullError("action queue is full")

        requested_at = _utc_now()
        reservation = self.store.reserve(
            action_id=str(uuid4()),
            request_id=str(action_request.request_id),
            caller="homelab-dashboard",
            source_address=source_address,
            target_id=target_id,
            display_name=display_name,
            action=action,
            reason=action_request.reason,
            requested_at=requested_at,
        )
        if not reservation.duplicate:
            try:
                self.queue.put_nowait(str(reservation.record.action_id))
            except asyncio.QueueFull as error:  # pragma: no cover - no await in reservation path
                raise ActionQueueFullError("action queue is full") from error
        return _accepted_response(reservation.record)

    async def wait_until_idle(self) -> None:
        await self.queue.join()

    async def _worker(self, worker_index: int) -> None:
        while True:
            action_id = await self.queue.get()
            try:
                await self._execute(action_id)
            except asyncio.CancelledError:
                raise
            except Exception:
                logger.exception("Dashboard action worker %s failed", worker_index)
            finally:
                self.queue.task_done()

    async def _execute(self, action_id: str) -> None:
        record = self.store.get(action_id)
        if record is None or record.status != "queued":
            return
        target = self.registry.get_service(record.target_id)
        wake_target = self.registry.get_wake_target()
        if target is not None:
            timeout_seconds = target.timeout_seconds
        elif wake_target is not None and wake_target.id == record.target_id:
            timeout_seconds = wake_target.timeout_seconds
        else:
            self.store.mark_running(action_id, started_at=_utc_now())
            self.store.finish(
                action_id,
                status="rejected",
                finished_at=_utc_now(),
                result_summary="Target is no longer present in the action registry.",
                error_code="target_unavailable",
                duration_ms=0,
                previous_state=None,
                resulting_state=None,
            )
            return

        running_record = self.store.mark_running(action_id, started_at=_utc_now())
        started = monotonic()
        try:
            result = await self.helper.execute(
                running_record,
                timeout_seconds=timeout_seconds,
            )
        except asyncio.CancelledError:
            self._finish_cancelled(action_id, started)
            raise
        except HelperProtocolError:
            logger.error("Dashboard action helper protocol validation failed")
            result = HelperExecutionResult(
                status="failed",
                summary="Action helper returned an invalid response.",
                error_code="helper_protocol_error",
            )
        except Exception as error:  # pragma: no cover - defensive boundary
            logger.error("Dashboard action helper failed (%s)", type(error).__name__)
            result = HelperExecutionResult(
                status="failed",
                summary="Action helper was unavailable.",
                error_code="helper_unavailable",
            )

        duration_ms = round((monotonic() - started) * 1000)
        try:
            self.store.finish(
                action_id,
                status=result.status,
                finished_at=_utc_now(),
                result_summary=result.summary,
                error_code=result.error_code,
                duration_ms=duration_ms,
                previous_state=result.previous_state,
                resulting_state=result.resulting_state,
            )
        except StateTransitionError:
            logger.error("Dashboard action completion state was already changed")

    def _finish_cancelled(self, action_id: str, started: float) -> None:
        try:
            self.store.finish(
                action_id,
                status="failed",
                finished_at=_utc_now(),
                result_summary="Action service stopped before completion.",
                error_code="action_service_stopped",
                duration_ms=round((monotonic() - started) * 1000),
                previous_state=None,
                resulting_state=None,
            )
        except StateTransitionError:
            pass


def _accepted_response(record: ActionRecordResponse) -> ActionAcceptedResponse:
    return ActionAcceptedResponse(
        action_id=record.action_id,
        request_id=record.request_id,
        target_id=record.target_id,
        action=record.action,
        status=record.status,
        accepted_at=record.requested_at,
        polling_location=f"/actions/{record.action_id}",
    )


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)
