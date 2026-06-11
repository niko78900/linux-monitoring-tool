from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
import math

from app.models.history import (
    DiskHistoryPoint,
    DiskHistoryResponse,
    HistoryRange,
    HistoryRangeOption,
    HistoryRangesResponse,
    OverviewHistoryPoint,
    OverviewHistoryResponse,
    RaidHistoryPoint,
    RaidHistoryResponse,
    StorageHistoryPoint,
    StorageHistoryResponse,
)
from app.services.history_store import HistoryStore

RANGE_SECONDS: dict[HistoryRange, int] = {
    "1h": 3600,
    "24h": 86400,
    "7d": 7 * 86400,
    "30d": 30 * 86400,
}

RANGE_OPTIONS: tuple[HistoryRangeOption, ...] = (
    HistoryRangeOption(key="1h", label="1 hour", duration_seconds=3600),
    HistoryRangeOption(key="24h", label="24 hours", duration_seconds=86400),
    HistoryRangeOption(key="7d", label="7 days", duration_seconds=7 * 86400),
    HistoryRangeOption(key="30d", label="30 days", duration_seconds=30 * 86400),
)

_RESOLUTION_CHOICES = (60, 120, 300, 600, 900, 1800, 3600, 7200, 14400, 21600, 43200, 86400)


@dataclass(frozen=True)
class HistoryWindow:
    range_key: HistoryRange
    from_timestamp: datetime
    to_timestamp: datetime
    resolution_seconds: int
    max_points: int


def build_ranges_response(max_points_cap: int) -> HistoryRangesResponse:
    return HistoryRangesResponse(
        default_range="24h",
        max_points_cap=max_points_cap,
        ranges=list(RANGE_OPTIONS),
    )


def resolve_window(
    range_key: HistoryRange,
    max_points: int,
    max_points_cap: int,
    *,
    now_utc: datetime | None = None,
) -> HistoryWindow:
    to_timestamp = (now_utc or datetime.now(timezone.utc)).replace(microsecond=0)
    from_timestamp = to_timestamp - timedelta(seconds=RANGE_SECONDS[range_key])
    clamped_points = max(1, min(max_points, max_points_cap))
    target_resolution = max(1, math.ceil(RANGE_SECONDS[range_key] / clamped_points))
    resolution_seconds = next(
        (value for value in _RESOLUTION_CHOICES if value >= target_resolution),
        _RESOLUTION_CHOICES[-1],
    )
    return HistoryWindow(
        range_key=range_key,
        from_timestamp=from_timestamp,
        to_timestamp=to_timestamp,
        resolution_seconds=resolution_seconds,
        max_points=clamped_points,
    )


def get_overview_history(
    store: HistoryStore,
    window: HistoryWindow,
) -> OverviewHistoryResponse:
    rows = store.fetch_all(
        f"""
        SELECT
            ((timestamp_utc / ?) * ?) AS bucket_timestamp,
            AVG(cpu_percent) AS cpu_percent_avg,
            MAX(cpu_percent) AS cpu_percent_max,
            AVG(cpu_temperature_c) AS cpu_temperature_c_avg,
            MAX(cpu_temperature_c) AS cpu_temperature_c_max,
            AVG(memory_percent) AS memory_percent_avg,
            AVG(swap_percent) AS swap_percent_avg,
            AVG(gpu_utilization_percent) AS gpu_utilization_percent_avg,
            AVG(gpu_temperature_c) AS gpu_temperature_c_avg,
            AVG(gpu_memory_used_mb) AS gpu_memory_used_mb_avg,
            AVG(gpu_power_usage_w) AS gpu_power_usage_w_avg,
            AVG(network_recv_bytes_per_second) AS network_recv_bytes_per_second_avg,
            AVG(network_send_bytes_per_second) AS network_send_bytes_per_second_avg,
            AVG(running_containers) AS running_containers_avg
        FROM metric_samples
        WHERE timestamp_utc BETWEEN ? AND ?
        GROUP BY bucket_timestamp
        ORDER BY bucket_timestamp ASC
        """,
        (
            window.resolution_seconds,
            window.resolution_seconds,
            int(window.from_timestamp.timestamp()),
            int(window.to_timestamp.timestamp()),
        ),
    )

    return OverviewHistoryResponse(
        range=window.range_key,
        **{
            "from": window.from_timestamp,
            "to": window.to_timestamp,
        },
        resolution_seconds=window.resolution_seconds,
        max_points=window.max_points,
        points=[
            OverviewHistoryPoint(
                timestamp=_to_datetime(row["bucket_timestamp"]),
                cpu_percent_avg=_float(row["cpu_percent_avg"]),
                cpu_percent_max=_float(row["cpu_percent_max"]),
                cpu_temperature_c_avg=_float(row["cpu_temperature_c_avg"]),
                cpu_temperature_c_max=_float(row["cpu_temperature_c_max"]),
                memory_percent_avg=_float(row["memory_percent_avg"]),
                swap_percent_avg=_float(row["swap_percent_avg"]),
                gpu_utilization_percent_avg=_float(row["gpu_utilization_percent_avg"]),
                gpu_temperature_c_avg=_float(row["gpu_temperature_c_avg"]),
                gpu_memory_used_mb_avg=_float(row["gpu_memory_used_mb_avg"]),
                gpu_power_usage_w_avg=_float(row["gpu_power_usage_w_avg"]),
                network_recv_bytes_per_second_avg=_float(
                    row["network_recv_bytes_per_second_avg"]
                ),
                network_send_bytes_per_second_avg=_float(
                    row["network_send_bytes_per_second_avg"]
                ),
                running_containers_avg=_float(row["running_containers_avg"]),
            )
            for row in rows
        ],
    )


def get_storage_history(
    store: HistoryStore,
    window: HistoryWindow,
    mountpoint: str,
) -> StorageHistoryResponse:
    rows = store.fetch_all(
        f"""
        SELECT
            ((timestamp_utc / ?) * ?) AS bucket_timestamp,
            AVG(used_bytes) AS used_bytes_avg,
            AVG(free_bytes) AS free_bytes_avg,
            AVG(total_bytes) AS total_bytes_avg,
            AVG(percent) AS percent_avg,
            MAX(percent) AS percent_max,
            MAX(read_only) AS read_only_any,
            MAX(available) AS available_any,
            MAX(
                CASE health_status
                    WHEN 'critical' THEN 3
                    WHEN 'warning' THEN 2
                    WHEN 'healthy' THEN 1
                    ELSE 0
                END
            ) AS health_status_rank
        FROM filesystem_samples
        WHERE mountpoint = ? AND timestamp_utc BETWEEN ? AND ?
        GROUP BY bucket_timestamp
        ORDER BY bucket_timestamp ASC
        """,
        (
            window.resolution_seconds,
            window.resolution_seconds,
            mountpoint,
            int(window.from_timestamp.timestamp()),
            int(window.to_timestamp.timestamp()),
        ),
    )

    return StorageHistoryResponse(
        range=window.range_key,
        mountpoint=mountpoint,
        **{
            "from": window.from_timestamp,
            "to": window.to_timestamp,
        },
        resolution_seconds=window.resolution_seconds,
        max_points=window.max_points,
        points=[
            StorageHistoryPoint(
                timestamp=_to_datetime(row["bucket_timestamp"]),
                used_bytes_avg=_float(row["used_bytes_avg"]),
                free_bytes_avg=_float(row["free_bytes_avg"]),
                total_bytes_avg=_float(row["total_bytes_avg"]),
                percent_avg=_float(row["percent_avg"]),
                percent_max=_float(row["percent_max"]),
                read_only_any=bool(row["read_only_any"]),
                available_any=bool(row["available_any"]),
                health_status=_severity_to_status(int(row["health_status_rank"])),
            )
            for row in rows
        ],
    )


def get_disk_history(
    store: HistoryStore,
    window: HistoryWindow,
    device: str,
) -> DiskHistoryResponse:
    rows = store.fetch_all(
        f"""
        SELECT
            ((timestamp_utc / ?) * ?) AS bucket_timestamp,
            AVG(temperature_c) AS temperature_c_avg,
            MAX(
                CASE health_status
                    WHEN 'critical' THEN 3
                    WHEN 'warning' THEN 2
                    WHEN 'healthy' THEN 1
                    ELSE 0
                END
            ) AS health_status_rank,
            MAX(kernel_state) AS kernel_state
        FROM physical_disk_samples
        WHERE device = ? AND timestamp_utc BETWEEN ? AND ?
        GROUP BY bucket_timestamp
        ORDER BY bucket_timestamp ASC
        """,
        (
            window.resolution_seconds,
            window.resolution_seconds,
            device,
            int(window.from_timestamp.timestamp()),
            int(window.to_timestamp.timestamp()),
        ),
    )

    return DiskHistoryResponse(
        range=window.range_key,
        device=device,
        **{
            "from": window.from_timestamp,
            "to": window.to_timestamp,
        },
        resolution_seconds=window.resolution_seconds,
        max_points=window.max_points,
        points=[
            DiskHistoryPoint(
                timestamp=_to_datetime(row["bucket_timestamp"]),
                temperature_c_avg=_float(row["temperature_c_avg"]),
                health_status=_severity_to_status(int(row["health_status_rank"])),
                kernel_state=row["kernel_state"],
            )
            for row in rows
        ],
    )


def get_raid_history(
    store: HistoryStore,
    window: HistoryWindow,
    array_name: str,
) -> RaidHistoryResponse:
    rows = store.fetch_all(
        f"""
        SELECT
            ((timestamp_utc / ?) * ?) AS bucket_timestamp,
            AVG(active_devices) AS active_devices_avg,
            AVG(degraded_devices) AS degraded_devices_avg,
            MAX(state) AS state,
            MAX(sync_action) AS sync_action,
            MAX(
                CASE health_status
                    WHEN 'critical' THEN 3
                    WHEN 'warning' THEN 2
                    WHEN 'healthy' THEN 1
                    ELSE 0
                END
            ) AS health_status_rank
        FROM raid_samples
        WHERE array_name = ? AND timestamp_utc BETWEEN ? AND ?
        GROUP BY bucket_timestamp
        ORDER BY bucket_timestamp ASC
        """,
        (
            window.resolution_seconds,
            window.resolution_seconds,
            array_name,
            int(window.from_timestamp.timestamp()),
            int(window.to_timestamp.timestamp()),
        ),
    )

    return RaidHistoryResponse(
        range=window.range_key,
        array_name=array_name,
        **{
            "from": window.from_timestamp,
            "to": window.to_timestamp,
        },
        resolution_seconds=window.resolution_seconds,
        max_points=window.max_points,
        points=[
            RaidHistoryPoint(
                timestamp=_to_datetime(row["bucket_timestamp"]),
                active_devices_avg=_float(row["active_devices_avg"]),
                degraded_devices_avg=_float(row["degraded_devices_avg"]),
                state=row["state"],
                sync_action=row["sync_action"],
                health_status=_severity_to_status(int(row["health_status_rank"])),
            )
            for row in rows
        ],
    )


def _to_datetime(timestamp_utc: int) -> datetime:
    return datetime.fromtimestamp(int(timestamp_utc), tz=timezone.utc)


def _float(value: object) -> float | None:
    if value is None:
        return None
    return float(value)


def _severity_to_status(value: int) -> str:
    return {
        3: "critical",
        2: "warning",
        1: "healthy",
    }.get(value, "unknown")
