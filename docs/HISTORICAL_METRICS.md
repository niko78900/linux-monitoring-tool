# Historical Metrics

Phase B adds persistent server-side historical telemetry to the monitoring backend.

## Scope

History currently records:

- overview metrics from the Debian monitoring host
- mounted filesystem usage snapshots
- physical disk health and temperatures
- RAID array state snapshots

The monitoring API remains read-only. History endpoints are `GET` only.

## Configuration

Backend environment variables:

```text
HISTORY_ENABLED=true
HISTORY_DB_PATH=/var/lib/linux-monitoring/history.sqlite3
HISTORY_SAMPLE_INTERVAL_SECONDS=60
HISTORY_RETENTION_DAYS=30
HISTORY_RETENTION_CLEANUP_INTERVAL_SECONDS=3600
HISTORY_MAX_RESPONSE_POINTS=720
```

SQLite behavior:

```text
PRAGMA journal_mode=WAL;
PRAGMA busy_timeout=5000;
```

## Sampling model

The backend runs one in-process background collector.

Behavior:

- first sample occurs shortly after startup
- later samples run on the configured interval
- samples are independent of client polling
- overlapping samples are prevented
- cleanup removes rows older than the retention window
- collection failures are logged and swallowed so live endpoints keep working

## Endpoints

```text
GET /api/history/ranges
GET /api/history/overview?range=24h&max_points=360
GET /api/history/storage?range=24h&mountpoint=/mnt/storage&max_points=360
GET /api/history/disks?range=24h&device=/dev/sda&max_points=360
GET /api/history/raid?range=7d&array=md0&max_points=360
```

Supported ranges:

```text
1h
24h
7d
30d
```

Responses are bucketed server-side and `max_points` is clamped to `HISTORY_MAX_RESPONSE_POINTS`.

## Throughput calculation

Network throughput is derived from consecutive stored counter samples:

```text
receive_bytes_per_second =
  max(0, current_received_total - previous_received_total) / elapsed_seconds

send_bytes_per_second =
  max(0, current_sent_total - previous_sent_total) / elapsed_seconds
```

First-sample, counter-reset, negative-delta, and zero-elapsed-time cases return zero throughput instead of spikes.
