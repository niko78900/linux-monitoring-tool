from __future__ import annotations

import asyncio
import logging
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Callable

from app.core.config import Settings
from app.models.docker import DockerSummaryResponse
from app.models.gpu import GPUResponse
from app.models.system import SystemResponse
from app.services.docker_service import get_docker_summary
from app.services.gpu_service import get_gpu_metrics
from app.services.history_store import (
    FilesystemSampleRecord,
    HistorySnapshot,
    HistoryStore,
    LatestCounterSample,
    MetricSampleRecord,
    PhysicalDiskSampleRecord,
    RaidSampleRecord,
)
from app.services.system_service import get_system_metrics

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class ThroughputSample:
    send_bytes_per_second: float
    recv_bytes_per_second: float


class HistoryCollector:
    def __init__(
        self,
        *,
        settings: Settings,
        store: HistoryStore,
        get_system_metrics_fn: Callable[[str], SystemResponse],
        get_gpu_metrics_fn: Callable[[], GPUResponse],
        get_docker_summary_fn: Callable[[], DockerSummaryResponse],
        initial_delay_seconds: float = 1.0,
    ):
        self._settings = settings
        self._store = store
        self._get_system_metrics = get_system_metrics_fn
        self._get_gpu_metrics = get_gpu_metrics_fn
        self._get_docker_summary = get_docker_summary_fn
        self._initial_delay_seconds = initial_delay_seconds
        self._task: asyncio.Task[None] | None = None
        self._collect_lock = asyncio.Lock()
        self._stop_event = asyncio.Event()
        self._last_cleanup_at: datetime | None = None
        self._previous_counter_sample: LatestCounterSample | None = None

    async def start(self) -> None:
        self._store.initialize()
        self._previous_counter_sample = self._store.get_latest_counter_sample()
        if self._task is None:
            self._task = asyncio.create_task(self._run(), name="history-collector")

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

    async def collect_once(self) -> None:
        async with self._collect_lock:
            started_at = datetime.now(timezone.utc)
            try:
                system_metrics = await asyncio.to_thread(
                    self._get_system_metrics,
                    self._settings.disk_mountpoint,
                )
                gpu_metrics = await asyncio.to_thread(self._get_gpu_metrics)
                docker_summary = await asyncio.to_thread(self._get_docker_summary)
                snapshot = build_history_snapshot(
                    system_metrics=system_metrics,
                    gpu_metrics=gpu_metrics,
                    docker_summary=docker_summary,
                    previous_counter_sample=self._previous_counter_sample,
                    sampled_at=started_at,
                )
                await asyncio.to_thread(self._store.insert_snapshot, snapshot)
                self._previous_counter_sample = LatestCounterSample(
                    timestamp_utc=snapshot.metric.timestamp_utc,
                    bytes_sent_total=snapshot.metric.network_bytes_sent_total,
                    bytes_recv_total=snapshot.metric.network_bytes_recv_total,
                )
                await self._maybe_cleanup(now_utc=started_at)
            except Exception:
                logger.exception("History sample collection failed.")

    @property
    def task(self) -> asyncio.Task[None] | None:
        return self._task

    async def _run(self) -> None:
        if self._initial_delay_seconds > 0:
            await asyncio.sleep(self._initial_delay_seconds)

        while not self._stop_event.is_set():
            await self.collect_once()
            await asyncio.sleep(self._settings.history_sample_interval_seconds)

    async def _maybe_cleanup(self, *, now_utc: datetime) -> None:
        last_cleanup = self._last_cleanup_at
        if last_cleanup is not None:
            elapsed = (now_utc - last_cleanup).total_seconds()
            if elapsed < self._settings.history_retention_cleanup_interval_seconds:
                return
        await asyncio.to_thread(
            self._store.cleanup_expired,
            self._settings.history_retention_days,
            now_utc=now_utc,
        )
        self._last_cleanup_at = now_utc


def calculate_throughput(
    *,
    current_timestamp_utc: int,
    current_bytes_sent_total: int,
    current_bytes_recv_total: int,
    previous_counter_sample: LatestCounterSample | None,
) -> ThroughputSample:
    if previous_counter_sample is None:
        return ThroughputSample(send_bytes_per_second=0.0, recv_bytes_per_second=0.0)

    elapsed_seconds = current_timestamp_utc - previous_counter_sample.timestamp_utc
    if elapsed_seconds <= 0:
        return ThroughputSample(send_bytes_per_second=0.0, recv_bytes_per_second=0.0)

    sent_delta = current_bytes_sent_total - previous_counter_sample.bytes_sent_total
    recv_delta = current_bytes_recv_total - previous_counter_sample.bytes_recv_total
    if sent_delta < 0 or recv_delta < 0:
        return ThroughputSample(send_bytes_per_second=0.0, recv_bytes_per_second=0.0)

    return ThroughputSample(
        send_bytes_per_second=sent_delta / elapsed_seconds,
        recv_bytes_per_second=recv_delta / elapsed_seconds,
    )


def build_history_snapshot(
    *,
    system_metrics: SystemResponse,
    gpu_metrics: GPUResponse,
    docker_summary: DockerSummaryResponse,
    previous_counter_sample: LatestCounterSample | None,
    sampled_at: datetime,
) -> HistorySnapshot:
    sampled_timestamp_utc = int(sampled_at.astimezone(timezone.utc).timestamp())
    throughput = calculate_throughput(
        current_timestamp_utc=sampled_timestamp_utc,
        current_bytes_sent_total=system_metrics.network.bytes_sent,
        current_bytes_recv_total=system_metrics.network.bytes_recv,
        previous_counter_sample=previous_counter_sample,
    )

    metric = MetricSampleRecord(
        timestamp_utc=sampled_timestamp_utc,
        hostname=system_metrics.hostname,
        cpu_percent=system_metrics.cpu.usage_percent,
        cpu_temperature_c=system_metrics.cpu.temperature_c,
        chassis_temperature_c=system_metrics.chassis_temperature_c,
        memory_percent=system_metrics.memory.percent,
        memory_used_bytes=system_metrics.memory.used,
        memory_total_bytes=system_metrics.memory.total,
        swap_percent=system_metrics.swap.percent,
        swap_used_bytes=system_metrics.swap.used,
        swap_total_bytes=system_metrics.swap.total,
        primary_disk_percent=system_metrics.disk.percent,
        gpu_available=gpu_metrics.available,
        gpu_utilization_percent=gpu_metrics.utilization_percent if gpu_metrics.available else None,
        gpu_temperature_c=gpu_metrics.temperature_c if gpu_metrics.available else None,
        gpu_memory_used_mb=gpu_metrics.memory_used_mb if gpu_metrics.available else None,
        gpu_memory_total_mb=gpu_metrics.memory_total_mb if gpu_metrics.available else None,
        gpu_power_usage_w=gpu_metrics.power_usage_w if gpu_metrics.available else None,
        gpu_fan_speed_percent=gpu_metrics.fan_speed_percent if gpu_metrics.available else None,
        network_bytes_sent_total=system_metrics.network.bytes_sent,
        network_bytes_recv_total=system_metrics.network.bytes_recv,
        network_send_bytes_per_second=throughput.send_bytes_per_second,
        network_recv_bytes_per_second=throughput.recv_bytes_per_second,
        running_containers=docker_summary.running_containers,
    )

    filesystems = [
        FilesystemSampleRecord(
            timestamp_utc=sampled_timestamp_utc,
            mountpoint=item.mountpoint,
            device=item.device,
            filesystem=item.fstype,
            used_bytes=item.used,
            free_bytes=item.free,
            total_bytes=item.total,
            percent=item.percent,
            read_only=item.read_only,
            available=item.available,
            health_status=item.health.status,
        )
        for item in system_metrics.disks
    ]
    physical_disks = [
        PhysicalDiskSampleRecord(
            timestamp_utc=sampled_timestamp_utc,
            device=item.device,
            model=item.model,
            temperature_c=item.temperature_c,
            health_status=item.health.status,
            kernel_state=item.state,
        )
        for item in system_metrics.physical_disks
    ]
    raid_arrays = [
        RaidSampleRecord(
            timestamp_utc=sampled_timestamp_utc,
            array_name=item.name,
            device=item.device,
            level=item.level,
            state=item.state,
            active_devices=item.active_devices,
            degraded_devices=item.degraded_devices,
            sync_action=item.sync_action,
            health_status=item.health.status,
        )
        for item in system_metrics.raid_arrays
    ]
    return HistorySnapshot(
        metric=metric,
        filesystems=filesystems,
        physical_disks=physical_disks,
        raid_arrays=raid_arrays,
    )


def create_history_collector(settings: Settings) -> HistoryCollector:
    return HistoryCollector(
        settings=settings,
        store=HistoryStore(settings.history_db_path),
        get_system_metrics_fn=get_system_metrics,
        get_gpu_metrics_fn=get_gpu_metrics,
        get_docker_summary_fn=get_docker_summary,
    )
