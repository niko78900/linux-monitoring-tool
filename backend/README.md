# linux-monitor backend (FastAPI)

Monitoring API for local-network dashboards, historical metrics, backend-owned alert evaluation, and mobile FCM delivery.

## Project layout

```
backend/
  app/
    api/
      routes/
    core/
    models/
    services/
    main.py
  .env.example
  requirements.txt
  run.py
```

## 1) Create virtual environment

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
pip install -r requirements.txt
```

Windows PowerShell:

```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\python.exe -m ensurepip --upgrade
.\.venv\Scripts\python.exe -m pip install --upgrade pip
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
```

## 2) Configure environment

```bash
cp .env.example .env
```

Adjust `.env` values if needed:

- `CORS_ORIGINS`: comma-separated frontend origins
- `CORS_ORIGIN_REGEX`: optional regex for additional frontend origins
- `DISK_MOUNTPOINT`: disk mount to report (default `/`)
- `HOST`/`PORT`: bind address and port
- `DOCKER_TIMEOUT_SECONDS`: Docker SDK timeout for daemon calls (default `3`)
- `HISTORY_ENABLED`: enable or disable persistent history collection
- `HISTORY_DB_PATH`: SQLite history database path
- `HISTORY_SAMPLE_INTERVAL_SECONDS`: background history sample interval
- `HISTORY_RETENTION_DAYS`: retention window for history rows
- `HISTORY_RETENTION_CLEANUP_INTERVAL_SECONDS`: cleanup cadence for old history rows
- `HISTORY_MAX_RESPONSE_POINTS`: upper bound for history response bucketing
- `ALERTS_ENABLED`: enable or disable the backend alert monitor
- `ALERT_DB_PATH`: SQLite alert database path
- `ALERT_GRACE_SECONDS`: sustained breach window before an active alert event
- `CPU_ALERT_THRESHOLD`, `MEMORY_ALERT_THRESHOLD`, `DISK_ALERT_THRESHOLD`
- `GPU_USAGE_ALERT_THRESHOLD`, `GPU_TEMP_ALERT_THRESHOLD`
- `MOBILE_PUSH_ENABLED`: enable backend FCM outbox delivery
- `FIREBASE_SERVICE_ACCOUNT_FILE`: backend-readable Firebase Admin credential
- `MOBILE_ALERT_API_TOKEN`: scoped token for tablet registration/status/test
- `ALERT_CONSUMER_API_TOKEN`: scoped token for alert event consumers such as the Discord bot

## 3) Run the API

```bash
python run.py
```

Default URL:

- API root: `http://localhost:4040/api`
- Docs: `http://localhost:4040/api/docs`

With default `HOST=0.0.0.0`, the API is also reachable via LAN/Tailscale at
`http://<server-ip>:4040/api`.

### CORS notes

- For same-origin production deployments (frontend and backend behind one reverse proxy), keep CORS strict.
- For separate frontend/backend origins, set `CORS_ORIGINS` to exact frontend origins.
- Use `CORS_ORIGIN_REGEX` only when you need pattern-based dev origins (for example dynamic LAN/Tailscale IPs).

## 4) Test endpoints

```bash
curl http://localhost:4040/api/health
curl http://localhost:4040/api/system
curl http://localhost:4040/api/gpu
curl http://localhost:4040/api/docker
curl http://localhost:4040/api/summary
curl http://localhost:4040/api/history/ranges
curl "http://localhost:4040/api/history/overview?range=24h"
curl -H "Authorization: Bearer <consumer-token>" http://localhost:4040/api/alerts/status
curl -H "Authorization: Bearer <mobile-token>" http://localhost:4040/api/mobile-alerts/status
```

`/api/system` now includes:

- `specs`: static hardware-oriented system specs:
  - `cpu.model_name`, `cpu.vendor`, `cpu.architecture`
  - `cpu.physical_cores`, `cpu.logical_cores`
  - `cpu.min_frequency_mhz`, `cpu.max_frequency_mhz` (when available)
  - `cpu.capabilities` (instruction-set/feature flags from `/proc/cpuinfo` on Linux)
  - `memory_total_bytes`, `swap_total_bytes`
  - `memory`: RAM inventory (total bytes, speed, type, detected vendors, module list when available)
  - `motherboard`: board vendor/model/version and chipset hint (from DMI/sysfs when available)
  - `gpu`: static GPU metadata (brand/model/driver, total VRAM, capability list)
- `disk`: primary disk (configured `DISK_MOUNTPOINT`, kept for compatibility)
- `disks`: all detected mounted disks/partitions with:
  - `device`, `mountpoint`, `fstype`
  - `total`, `used`, `free`, `percent`
  - `available`, `read_only`
  - `raid_array`, `raid_level` when a mounted filesystem is on an MD RAID device
  - `health.status` (`healthy`, `warning`, `critical`, `unknown`) and `health.reason`
- `raid_arrays`: detected Linux MD arrays with level, state, sync status, members, and health
- `physical_disks`: detected physical block devices with:
  - `device`, `model`, `vendor`, `serial`, `size_bytes`
  - `rotational`, `removable`, `state`
  - `mounted_partitions`, `raid_arrays`
  - `health.status` and `health.reason`
- `network.top_speed_mbps`: highest detected link speed from network interfaces (if available)

Disk list intentionally excludes pseudo/system mounts and EFI boot mountpoints such as `/boot/efi`.

## Notes on permissions

- Docker data requires access to Docker Engine socket (`/var/run/docker.sock` on Linux).
  - Add your user to the `docker` group or run with elevated privileges.
- NVIDIA metrics require:
  - NVIDIA drivers installed
  - NVML library available on host
  - process permission to access NVIDIA device files
- If Docker/NVIDIA access is missing, endpoints return `available: false` style responses instead of crashing.
- History and alert collection run in background tasks and should not break live telemetry endpoints if persistence, Firebase, Docker, or GPU collection fails.
- Mobile registration and alert-consumer endpoints use scoped bearer tokens separate from the control-agent token.
- FCM tokens are stored only in the backend-owned alert SQLite database and are never returned by status endpoints.
