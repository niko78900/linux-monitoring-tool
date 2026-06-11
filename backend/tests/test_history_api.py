from __future__ import annotations

from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest

from app.core.config import get_settings
from app.services.history_store import (
    FilesystemSampleRecord,
    HistorySnapshot,
    HistoryStore,
    MetricSampleRecord,
    PhysicalDiskSampleRecord,
    RaidSampleRecord,
    utc_timestamp,
)


@pytest.fixture
def history_db(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    path = tmp_path / "history.sqlite3"
    monkeypatch.setenv("HISTORY_DB_PATH", str(path))
    monkeypatch.setenv("HISTORY_MAX_RESPONSE_POINTS", "120")
    get_settings.cache_clear()
    return path


def test_history_ranges_endpoint_returns_supported_ranges(client, api_prefix: str, history_db: Path) -> None:
    response = client.get(f"{api_prefix}/history/ranges")

    assert response.status_code == 200
    payload = response.json()
    assert payload["default_range"] == "24h"
    assert [item["key"] for item in payload["ranges"]] == ["1h", "24h", "7d", "30d"]


def test_history_overview_rejects_invalid_range(client, api_prefix: str, history_db: Path) -> None:
    response = client.get(f"{api_prefix}/history/overview", params={"range": "12h"})

    assert response.status_code == 422


def test_history_overview_clamps_max_points(client, api_prefix: str, history_db: Path) -> None:
    _seed_history(history_db)

    response = client.get(
        f"{api_prefix}/history/overview",
        params={"range": "24h", "max_points": 9999},
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["max_points"] == 120


def test_history_endpoints_return_empty_points_for_empty_db(client, api_prefix: str, history_db: Path) -> None:
    response = client.get(f"{api_prefix}/history/overview", params={"range": "24h"})

    assert response.status_code == 200
    payload = response.json()
    assert payload["points"] == []


def test_history_overview_returns_aggregated_points(client, api_prefix: str, history_db: Path) -> None:
    _seed_history(history_db)

    response = client.get(
        f"{api_prefix}/history/overview",
        params={"range": "24h", "max_points": 24},
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["points"]
    point = payload["points"][0]
    assert point["cpu_percent_avg"] > 0
    assert point["network_recv_bytes_per_second_avg"] >= 0


def test_history_storage_filters_by_mountpoint(client, api_prefix: str, history_db: Path) -> None:
    _seed_history(history_db)

    response = client.get(
        f"{api_prefix}/history/storage",
        params={"range": "24h", "mountpoint": "/mnt/storage"},
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["mountpoint"] == "/mnt/storage"
    assert payload["points"][0]["percent_avg"] > 0


def test_history_disk_filters_by_device(client, api_prefix: str, history_db: Path) -> None:
    _seed_history(history_db)

    response = client.get(
        f"{api_prefix}/history/disks",
        params={"range": "24h", "device": "/dev/sda"},
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["device"] == "/dev/sda"
    assert payload["points"][0]["temperature_c_avg"] > 0


def test_history_raid_filters_by_array(client, api_prefix: str, history_db: Path) -> None:
    _seed_history(history_db)

    response = client.get(
        f"{api_prefix}/history/raid",
        params={"range": "24h", "array": "md0"},
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["array_name"] == "md0"
    assert payload["points"][0]["degraded_devices_avg"] == 0


def _seed_history(db_path: Path) -> None:
    store = HistoryStore(db_path)
    store.initialize()
    now = datetime.now(timezone.utc).replace(microsecond=0)
    for offset_hours in range(6):
        timestamp = now - timedelta(hours=offset_hours)
        sample_timestamp = utc_timestamp(timestamp)
        store.insert_snapshot(
            HistorySnapshot(
                metric=MetricSampleRecord(
                    timestamp_utc=sample_timestamp,
                    hostname="homelab-server",
                    cpu_percent=20.0 + offset_hours,
                    cpu_temperature_c=45.0 + offset_hours,
                    chassis_temperature_c=33.0,
                    memory_percent=50.0 + offset_hours,
                    memory_used_bytes=500 + offset_hours,
                    memory_total_bytes=1000,
                    swap_percent=5.0,
                    swap_used_bytes=50,
                    swap_total_bytes=1000,
                    primary_disk_percent=60.0,
                    gpu_available=True,
                    gpu_utilization_percent=10.0 + offset_hours,
                    gpu_temperature_c=50.0 + offset_hours,
                    gpu_memory_used_mb=1024 + offset_hours,
                    gpu_memory_total_mb=8192,
                    gpu_power_usage_w=100.0 + offset_hours,
                    gpu_fan_speed_percent=40,
                    network_bytes_sent_total=10_000 + (offset_hours * 100),
                    network_bytes_recv_total=20_000 + (offset_hours * 100),
                    network_send_bytes_per_second=200.0 + offset_hours,
                    network_recv_bytes_per_second=400.0 + offset_hours,
                    running_containers=5,
                ),
                filesystems=[
                    FilesystemSampleRecord(
                        timestamp_utc=sample_timestamp,
                        mountpoint="/mnt/storage",
                        device="/dev/md0",
                        filesystem="ext4",
                        used_bytes=600,
                        free_bytes=400,
                        total_bytes=1000,
                        percent=60.0 + offset_hours,
                        read_only=False,
                        available=True,
                        health_status="healthy",
                    )
                ],
                physical_disks=[
                    PhysicalDiskSampleRecord(
                        timestamp_utc=sample_timestamp,
                        device="/dev/sda",
                        model="Samsung SSD",
                        temperature_c=39.0 + offset_hours,
                        health_status="healthy",
                        kernel_state="running",
                    )
                ],
                raid_arrays=[
                    RaidSampleRecord(
                        timestamp_utc=sample_timestamp,
                        array_name="md0",
                        device="/dev/md0",
                        level="raid1",
                        state="clean",
                        active_devices=2,
                        degraded_devices=0,
                        sync_action="idle",
                        health_status="healthy",
                    )
                ],
            )
        )
