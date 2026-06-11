from __future__ import annotations

from datetime import datetime, timedelta, timezone
from pathlib import Path

from app.services.history_store import (
    FilesystemSampleRecord,
    HistorySnapshot,
    HistoryStore,
    MetricSampleRecord,
    PhysicalDiskSampleRecord,
    RaidSampleRecord,
    utc_timestamp,
)


def test_history_store_initializes_with_wal(tmp_path: Path) -> None:
    store = HistoryStore(tmp_path / "history.sqlite3")
    store.initialize()

    assert store.db_path.exists()
    assert store.read_pragma("journal_mode").lower() == "wal"


def test_history_store_inserts_and_reads_latest_counter(tmp_path: Path) -> None:
    store = HistoryStore(tmp_path / "history.sqlite3")
    store.initialize()
    snapshot = _sample_snapshot(datetime(2026, 6, 11, 20, tzinfo=timezone.utc))

    store.insert_snapshot(snapshot)

    latest = store.get_latest_counter_sample()
    assert latest is not None
    assert latest.bytes_sent_total == 2_000
    assert latest.bytes_recv_total == 4_000


def test_history_store_cleanup_removes_expired_rows(tmp_path: Path) -> None:
    store = HistoryStore(tmp_path / "history.sqlite3")
    store.initialize()
    old_snapshot = _sample_snapshot(datetime(2026, 5, 1, 20, tzinfo=timezone.utc))
    fresh_snapshot = _sample_snapshot(datetime(2026, 6, 11, 20, tzinfo=timezone.utc))

    store.insert_snapshot(old_snapshot)
    store.insert_snapshot(fresh_snapshot)
    store.cleanup_expired(
        30,
        now_utc=datetime(2026, 6, 11, 21, tzinfo=timezone.utc),
    )

    row = store.fetch_one("SELECT COUNT(*) AS count FROM metric_samples")
    assert row is not None
    assert int(row["count"]) == 1


def _sample_snapshot(timestamp: datetime) -> HistorySnapshot:
    sample_timestamp = utc_timestamp(timestamp)
    return HistorySnapshot(
        metric=MetricSampleRecord(
            timestamp_utc=sample_timestamp,
            hostname="homelab-server",
            cpu_percent=20.0,
            cpu_temperature_c=45.0,
            chassis_temperature_c=33.0,
            memory_percent=55.0,
            memory_used_bytes=55,
            memory_total_bytes=100,
            swap_percent=5.0,
            swap_used_bytes=5,
            swap_total_bytes=100,
            primary_disk_percent=60.0,
            gpu_available=True,
            gpu_utilization_percent=15.0,
            gpu_temperature_c=50.0,
            gpu_memory_used_mb=1024,
            gpu_memory_total_mb=8192,
            gpu_power_usage_w=110.0,
            gpu_fan_speed_percent=40,
            network_bytes_sent_total=2_000,
            network_bytes_recv_total=4_000,
            network_send_bytes_per_second=200.0,
            network_recv_bytes_per_second=400.0,
            running_containers=6,
        ),
        filesystems=[
            FilesystemSampleRecord(
                timestamp_utc=sample_timestamp,
                mountpoint="/mnt/storage",
                device="/dev/md0",
                filesystem="ext4",
                used_bytes=600,
                free_bytes=400,
                total_bytes=1_000,
                percent=60.0,
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
                temperature_c=39.0,
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
