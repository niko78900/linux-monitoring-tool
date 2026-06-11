from __future__ import annotations

import sqlite3
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from threading import Lock
from typing import Any


def utc_timestamp(value: datetime) -> int:
    return int(value.astimezone(timezone.utc).timestamp())


@dataclass(frozen=True)
class MetricSampleRecord:
    timestamp_utc: int
    hostname: str
    cpu_percent: float
    cpu_temperature_c: float | None
    chassis_temperature_c: float | None
    memory_percent: float
    memory_used_bytes: int
    memory_total_bytes: int
    swap_percent: float
    swap_used_bytes: int
    swap_total_bytes: int
    primary_disk_percent: float
    gpu_available: bool
    gpu_utilization_percent: float | None
    gpu_temperature_c: float | None
    gpu_memory_used_mb: int | None
    gpu_memory_total_mb: int | None
    gpu_power_usage_w: float | None
    gpu_fan_speed_percent: int | None
    network_bytes_sent_total: int
    network_bytes_recv_total: int
    network_send_bytes_per_second: float
    network_recv_bytes_per_second: float
    running_containers: int


@dataclass(frozen=True)
class FilesystemSampleRecord:
    timestamp_utc: int
    mountpoint: str
    device: str
    filesystem: str
    used_bytes: int
    free_bytes: int
    total_bytes: int
    percent: float
    read_only: bool
    available: bool
    health_status: str


@dataclass(frozen=True)
class PhysicalDiskSampleRecord:
    timestamp_utc: int
    device: str
    model: str | None
    temperature_c: float | None
    health_status: str
    kernel_state: str | None


@dataclass(frozen=True)
class RaidSampleRecord:
    timestamp_utc: int
    array_name: str
    device: str
    level: str
    state: str
    active_devices: int
    degraded_devices: int
    sync_action: str | None
    health_status: str


@dataclass(frozen=True)
class HistorySnapshot:
    metric: MetricSampleRecord
    filesystems: list[FilesystemSampleRecord] = field(default_factory=list)
    physical_disks: list[PhysicalDiskSampleRecord] = field(default_factory=list)
    raid_arrays: list[RaidSampleRecord] = field(default_factory=list)


@dataclass(frozen=True)
class LatestCounterSample:
    timestamp_utc: int
    bytes_sent_total: int
    bytes_recv_total: int


class HistoryStore:
    def __init__(self, db_path: Path):
        self._db_path = db_path
        self._lock = Lock()

    @property
    def db_path(self) -> Path:
        return self._db_path

    def initialize(self) -> None:
        self._db_path.parent.mkdir(parents=True, exist_ok=True)
        with self._connect() as connection:
            connection.execute("PRAGMA journal_mode=WAL;")
            connection.execute("PRAGMA busy_timeout=5000;")
            connection.executescript(
                """
                CREATE TABLE IF NOT EXISTS metric_samples (
                    timestamp_utc INTEGER NOT NULL,
                    hostname TEXT NOT NULL,
                    cpu_percent REAL NOT NULL,
                    cpu_temperature_c REAL,
                    chassis_temperature_c REAL,
                    memory_percent REAL NOT NULL,
                    memory_used_bytes INTEGER NOT NULL,
                    memory_total_bytes INTEGER NOT NULL,
                    swap_percent REAL NOT NULL,
                    swap_used_bytes INTEGER NOT NULL,
                    swap_total_bytes INTEGER NOT NULL,
                    primary_disk_percent REAL NOT NULL,
                    gpu_available INTEGER NOT NULL,
                    gpu_utilization_percent REAL,
                    gpu_temperature_c REAL,
                    gpu_memory_used_mb INTEGER,
                    gpu_memory_total_mb INTEGER,
                    gpu_power_usage_w REAL,
                    gpu_fan_speed_percent INTEGER,
                    network_bytes_sent_total INTEGER NOT NULL,
                    network_bytes_recv_total INTEGER NOT NULL,
                    network_send_bytes_per_second REAL NOT NULL,
                    network_recv_bytes_per_second REAL NOT NULL,
                    running_containers INTEGER NOT NULL
                );

                CREATE TABLE IF NOT EXISTS filesystem_samples (
                    timestamp_utc INTEGER NOT NULL,
                    mountpoint TEXT NOT NULL,
                    device TEXT NOT NULL,
                    filesystem TEXT NOT NULL,
                    used_bytes INTEGER NOT NULL,
                    free_bytes INTEGER NOT NULL,
                    total_bytes INTEGER NOT NULL,
                    percent REAL NOT NULL,
                    read_only INTEGER NOT NULL,
                    available INTEGER NOT NULL,
                    health_status TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS physical_disk_samples (
                    timestamp_utc INTEGER NOT NULL,
                    device TEXT NOT NULL,
                    model TEXT,
                    temperature_c REAL,
                    health_status TEXT NOT NULL,
                    kernel_state TEXT
                );

                CREATE TABLE IF NOT EXISTS raid_samples (
                    timestamp_utc INTEGER NOT NULL,
                    array_name TEXT NOT NULL,
                    device TEXT NOT NULL,
                    level TEXT NOT NULL,
                    state TEXT NOT NULL,
                    active_devices INTEGER NOT NULL,
                    degraded_devices INTEGER NOT NULL,
                    sync_action TEXT,
                    health_status TEXT NOT NULL
                );

                CREATE INDEX IF NOT EXISTS idx_metric_samples_timestamp
                    ON metric_samples(timestamp_utc);
                CREATE INDEX IF NOT EXISTS idx_filesystem_samples_mountpoint_timestamp
                    ON filesystem_samples(mountpoint, timestamp_utc);
                CREATE INDEX IF NOT EXISTS idx_physical_disk_samples_device_timestamp
                    ON physical_disk_samples(device, timestamp_utc);
                CREATE INDEX IF NOT EXISTS idx_raid_samples_array_timestamp
                    ON raid_samples(array_name, timestamp_utc);
                """
            )

    def read_pragma(self, pragma_name: str) -> str:
        with self._connect() as connection:
            row = connection.execute(f"PRAGMA {pragma_name};").fetchone()
        if row is None:
            return ""
        value = row[0]
        return "" if value is None else str(value)

    def insert_snapshot(self, snapshot: HistorySnapshot) -> None:
        metric = snapshot.metric
        with self._lock:
            with self._connect() as connection:
                connection.execute(
                    """
                    INSERT INTO metric_samples (
                        timestamp_utc, hostname, cpu_percent, cpu_temperature_c,
                        chassis_temperature_c, memory_percent, memory_used_bytes,
                        memory_total_bytes, swap_percent, swap_used_bytes,
                        swap_total_bytes, primary_disk_percent, gpu_available,
                        gpu_utilization_percent, gpu_temperature_c,
                        gpu_memory_used_mb, gpu_memory_total_mb,
                        gpu_power_usage_w, gpu_fan_speed_percent,
                        network_bytes_sent_total, network_bytes_recv_total,
                        network_send_bytes_per_second,
                        network_recv_bytes_per_second, running_containers
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        metric.timestamp_utc,
                        metric.hostname,
                        metric.cpu_percent,
                        metric.cpu_temperature_c,
                        metric.chassis_temperature_c,
                        metric.memory_percent,
                        metric.memory_used_bytes,
                        metric.memory_total_bytes,
                        metric.swap_percent,
                        metric.swap_used_bytes,
                        metric.swap_total_bytes,
                        metric.primary_disk_percent,
                        int(metric.gpu_available),
                        metric.gpu_utilization_percent,
                        metric.gpu_temperature_c,
                        metric.gpu_memory_used_mb,
                        metric.gpu_memory_total_mb,
                        metric.gpu_power_usage_w,
                        metric.gpu_fan_speed_percent,
                        metric.network_bytes_sent_total,
                        metric.network_bytes_recv_total,
                        metric.network_send_bytes_per_second,
                        metric.network_recv_bytes_per_second,
                        metric.running_containers,
                    ),
                )
                if snapshot.filesystems:
                    connection.executemany(
                        """
                        INSERT INTO filesystem_samples (
                            timestamp_utc, mountpoint, device, filesystem,
                            used_bytes, free_bytes, total_bytes, percent,
                            read_only, available, health_status
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                        [
                            (
                                item.timestamp_utc,
                                item.mountpoint,
                                item.device,
                                item.filesystem,
                                item.used_bytes,
                                item.free_bytes,
                                item.total_bytes,
                                item.percent,
                                int(item.read_only),
                                int(item.available),
                                item.health_status,
                            )
                            for item in snapshot.filesystems
                        ],
                    )
                if snapshot.physical_disks:
                    connection.executemany(
                        """
                        INSERT INTO physical_disk_samples (
                            timestamp_utc, device, model, temperature_c,
                            health_status, kernel_state
                        ) VALUES (?, ?, ?, ?, ?, ?)
                        """,
                        [
                            (
                                item.timestamp_utc,
                                item.device,
                                item.model,
                                item.temperature_c,
                                item.health_status,
                                item.kernel_state,
                            )
                            for item in snapshot.physical_disks
                        ],
                    )
                if snapshot.raid_arrays:
                    connection.executemany(
                        """
                        INSERT INTO raid_samples (
                            timestamp_utc, array_name, device, level, state,
                            active_devices, degraded_devices, sync_action,
                            health_status
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                        [
                            (
                                item.timestamp_utc,
                                item.array_name,
                                item.device,
                                item.level,
                                item.state,
                                item.active_devices,
                                item.degraded_devices,
                                item.sync_action,
                                item.health_status,
                            )
                            for item in snapshot.raid_arrays
                        ],
                    )

    def cleanup_expired(self, retention_days: int, *, now_utc: datetime | None = None) -> None:
        cutoff = utc_timestamp(now_utc or datetime.now(timezone.utc)) - (retention_days * 86400)
        with self._lock:
            with self._connect() as connection:
                for table_name in (
                    "metric_samples",
                    "filesystem_samples",
                    "physical_disk_samples",
                    "raid_samples",
                ):
                    connection.execute(
                        f"DELETE FROM {table_name} WHERE timestamp_utc < ?",
                        (cutoff,),
                    )

    def get_latest_counter_sample(self) -> LatestCounterSample | None:
        row = self.fetch_one(
            """
            SELECT
                timestamp_utc,
                network_bytes_sent_total,
                network_bytes_recv_total
            FROM metric_samples
            ORDER BY timestamp_utc DESC
            LIMIT 1
            """
        )
        if row is None:
            return None
        return LatestCounterSample(
            timestamp_utc=int(row["timestamp_utc"]),
            bytes_sent_total=int(row["network_bytes_sent_total"]),
            bytes_recv_total=int(row["network_bytes_recv_total"]),
        )

    def fetch_one(self, sql: str, params: tuple[Any, ...] = ()) -> sqlite3.Row | None:
        with self._connect() as connection:
            return connection.execute(sql, params).fetchone()

    def fetch_all(self, sql: str, params: tuple[Any, ...] = ()) -> list[sqlite3.Row]:
        with self._connect() as connection:
            rows = connection.execute(sql, params).fetchall()
        return rows

    def _connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self._db_path)
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA busy_timeout=5000;")
        return connection
