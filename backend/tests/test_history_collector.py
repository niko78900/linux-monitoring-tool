from __future__ import annotations

import asyncio
from datetime import datetime, timezone
from pathlib import Path

import pytest

from app.core.config import get_settings
from app.models.docker import DockerSummaryResponse
from app.models.gpu import GPUResponse
from app.models.system import SystemResponse
from app.services.history_collector import (
    HistoryCollector,
    ThroughputSample,
    build_history_snapshot,
    calculate_throughput,
)
from app.services.history_store import HistoryStore, LatestCounterSample
from tests.test_api_endpoints import _sample_system_payload


def test_calculate_throughput_handles_first_sample() -> None:
    throughput = calculate_throughput(
        current_timestamp_utc=100,
        current_bytes_sent_total=1_000,
        current_bytes_recv_total=2_000,
        previous_counter_sample=None,
    )
    assert throughput == ThroughputSample(0.0, 0.0)


def test_calculate_throughput_handles_counter_reset() -> None:
    throughput = calculate_throughput(
        current_timestamp_utc=200,
        current_bytes_sent_total=500,
        current_bytes_recv_total=500,
        previous_counter_sample=LatestCounterSample(
            timestamp_utc=100,
            bytes_sent_total=1_000,
            bytes_recv_total=2_000,
        ),
    )
    assert throughput == ThroughputSample(0.0, 0.0)


def test_build_history_snapshot_uses_previous_counter() -> None:
    system_metrics = SystemResponse.model_validate(_sample_system_payload())
    gpu_metrics = GPUResponse(
        available=True,
        reason=None,
        name="RTX 3070",
        temperature_c=50,
        utilization_percent=10.0,
        memory_total_mb=8192,
        memory_used_mb=1024,
        memory_free_mb=7168,
        power_usage_w=100.0,
        fan_speed_percent=35,
        driver_version="555.99",
    )
    docker_summary = DockerSummaryResponse(docker_available=True, running_containers=3)

    snapshot = build_history_snapshot(
        system_metrics=system_metrics,
        gpu_metrics=gpu_metrics,
        docker_summary=docker_summary,
        previous_counter_sample=LatestCounterSample(
            timestamp_utc=1_000,
            bytes_sent_total=123_456_000,
            bytes_recv_total=987_654_000,
        ),
        sampled_at=datetime.fromtimestamp(1_010, tz=timezone.utc),
    )

    assert snapshot.metric.network_send_bytes_per_second == pytest.approx(78.9, abs=0.01)
    assert snapshot.metric.network_recv_bytes_per_second == pytest.approx(32.1, abs=0.01)


@pytest.mark.anyio
async def test_history_collector_store_failure_does_not_raise(tmp_path: Path) -> None:
    class FailingStore(HistoryStore):
        def insert_snapshot(self, snapshot):  # type: ignore[override]
            raise OSError("disk full")

    store = FailingStore(tmp_path / "history.sqlite3")
    store.initialize()
    collector = HistoryCollector(
        settings=get_settings(),
        store=store,
        get_system_metrics_fn=lambda _mountpoint, **_kwargs: SystemResponse.model_validate(
            _sample_system_payload()
        ),
        get_gpu_metrics_fn=lambda: GPUResponse(available=False, reason="No GPU"),
        get_docker_summary_fn=lambda: DockerSummaryResponse(
            docker_available=True,
            running_containers=1,
        ),
        initial_delay_seconds=0,
    )

    await collector.collect_once()


@pytest.mark.anyio
async def test_history_collector_shutdown_cancels_background_task(tmp_path: Path) -> None:
    store = HistoryStore(tmp_path / "history.sqlite3")
    collector = HistoryCollector(
        settings=get_settings(),
        store=store,
        get_system_metrics_fn=lambda _mountpoint, **_kwargs: SystemResponse.model_validate(
            _sample_system_payload()
        ),
        get_gpu_metrics_fn=lambda: GPUResponse(available=False, reason="No GPU"),
        get_docker_summary_fn=lambda: DockerSummaryResponse(
            docker_available=True,
            running_containers=1,
        ),
        initial_delay_seconds=0,
    )

    await collector.start()
    await asyncio.sleep(0.01)
    task = collector.task
    await collector.stop()

    assert task is not None
    assert task.done()
