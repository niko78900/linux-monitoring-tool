from __future__ import annotations

import asyncio
import logging
from dataclasses import dataclass
from typing import Callable

from app.core.config import Settings
from app.models.docker import DockerSummaryResponse
from app.models.gpu import GPUResponse
from app.models.system import SystemResponse
from app.services.docker_service import get_docker_summary
from app.services.gpu_service import get_gpu_metrics
from app.services.system_service import get_system_metrics

from .firebase_sender import FirebaseMobilePushSender
from .mobile_push import MobilePushOutboxWorker
from .rules import evaluate_alerts
from .store import AlertStore

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class AlertMonitorStatus:
    running: bool


class AlertMonitor:
    def __init__(
        self,
        *,
        settings: Settings,
        store: AlertStore,
        push_worker: MobilePushOutboxWorker,
        get_system_metrics_fn: Callable[[str], SystemResponse],
        get_gpu_metrics_fn: Callable[[], GPUResponse],
        get_docker_summary_fn: Callable[[], DockerSummaryResponse],
        initial_delay_seconds: float = 1.0,
    ) -> None:
        self._settings = settings
        self._store = store
        self._push_worker = push_worker
        self._get_system_metrics = get_system_metrics_fn
        self._get_gpu_metrics = get_gpu_metrics_fn
        self._get_docker_summary = get_docker_summary_fn
        self._initial_delay_seconds = initial_delay_seconds
        self._task: asyncio.Task[None] | None = None
        self._evaluate_lock = asyncio.Lock()
        self._stop_event = asyncio.Event()

    async def start(self) -> None:
        self._store.initialize()
        if not self._settings.alerts_enabled:
            logger.info("Backend alert monitor disabled by configuration.")
            return
        if self._task is None:
            self._task = asyncio.create_task(self._run(), name="alert-monitor")

    async def stop(self) -> None:
        self._stop_event.set()
        task = self._task
        self._task = None
        if task is None:
            return
        task.cancel()
        try:
            await task
        except asyncio.CancelledError:
            pass

    @property
    def running(self) -> bool:
        task = self._task
        return task is not None and not task.done()

    @property
    def task(self) -> asyncio.Task[None] | None:
        return self._task

    async def collect_once(self) -> None:
        if self._evaluate_lock.locked():
            logger.warning("Skipping overlapping alert evaluation cycle.")
            return
        async with self._evaluate_lock:
            system_metrics: SystemResponse | None = None
            gpu_metrics: GPUResponse | None = None
            docker_summary: DockerSummaryResponse | None = None

            try:
                system_metrics = await asyncio.to_thread(
                    self._get_system_metrics,
                    self._settings.disk_mountpoint,
                )
            except Exception:
                logger.exception("System alert metric collection failed.")

            try:
                gpu_metrics = await asyncio.to_thread(self._get_gpu_metrics)
            except Exception:
                logger.exception("GPU alert metric collection failed.")

            try:
                docker_summary = await asyncio.to_thread(self._get_docker_summary)
            except Exception:
                logger.exception("Docker alert metric collection failed.")

            try:
                candidates = evaluate_alerts(
                    settings=self._settings,
                    system=system_metrics,
                    gpu=gpu_metrics,
                    docker=docker_summary,
                )
                events = await asyncio.to_thread(
                    self._store.transition_alerts,
                    candidates,
                    grace_seconds=self._settings.alert_grace_seconds,
                    mobile_push_enabled=self._settings.mobile_push_enabled,
                    include_recovery=self._settings.mobile_push_include_recovery,
                )
                if events:
                    logger.info("Created %s backend alert event(s).", len(events))
            except Exception:
                logger.exception("Backend alert state evaluation failed.")

            try:
                await self._push_worker.process_due()
            except Exception:
                logger.exception("Mobile push outbox processing failed.")

    async def _run(self) -> None:
        if self._initial_delay_seconds > 0:
            await asyncio.sleep(self._initial_delay_seconds)

        while not self._stop_event.is_set():
            await self.collect_once()
            try:
                await asyncio.wait_for(
                    self._stop_event.wait(),
                    timeout=self._settings.alert_poll_interval_seconds,
                )
            except asyncio.TimeoutError:
                continue


def create_alert_monitor(settings: Settings) -> AlertMonitor:
    store = AlertStore(settings.alert_db_path)
    sender = FirebaseMobilePushSender(settings.firebase_service_account_file)
    push_worker = MobilePushOutboxWorker(
        settings=settings,
        store=store,
        sender=sender,
    )
    return AlertMonitor(
        settings=settings,
        store=store,
        push_worker=push_worker,
        get_system_metrics_fn=get_system_metrics,
        get_gpu_metrics_fn=get_gpu_metrics,
        get_docker_summary_fn=get_docker_summary,
    )
