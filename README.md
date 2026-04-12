# Linux Monitoring

Read-only Linux homelab monitoring monorepo with a FastAPI backend, Angular dashboard, and Discord bot.

Read-only homelab monitoring stack built as a monorepo:

- `backend/`: FastAPI monitoring API
- `frontend/`: Angular dashboard UI
- `bot/`: Discord bot for slash commands, alerts, and scheduled status posts

## Why This Project

This project gives you one monitoring pipeline for local servers:

- **System telemetry**: CPU, memory, swap, uptime, disks, network, temperatures
- **Storage health context**: mounted disks, RAID arrays, physical disk inventory and health summaries
- **GPU telemetry**: NVIDIA metrics through NVML (when available)
- **Docker telemetry**: container inventory and runtime status (when available)
- **Discord integration**: proactive alerting and chat-accessible status

The API is intentionally **read-only** (`GET` endpoints only).

## Architecture

```text
+---------------------+          +-----------------------+
| Angular Frontend    |  GET     | FastAPI Backend       |
| :4041               +--------->+ :4040/api/*           |
| (polling dashboard) |          | system/gpu/docker/... |
+----------+----------+          +-----+-----------------+
           |                           |
           |                           |
           |                           +--> psutil (CPU/RAM/disk/net)
           |                           +--> Linux sysfs (/sys, /proc)
           |                           +--> smartctl (optional disk temps)
           |                           +--> Docker SDK (optional)
           |                           +--> NVML (optional NVIDIA)
           |
           | slash commands + alerts (independent process)
           v
+---------------------+      GET      +-----------------------+
| Discord Bot         +-------------->+ FastAPI Backend       |
| (discord.py)        |               | :4040/api/*           |
+---------------------+               +-----------------------+
```

## Repository Layout

```text
linux-monitoring/
  README.md
  backend/
    app/
      api/routes/
      core/
      models/
      services/
    tests/
    run.py
  frontend/
    src/app/
      core/
      features/dashboard/
      shared/
    proxy.conf.json
  bot/
    src/
    tests/
```

## API Endpoints

Backend exposes these endpoints under `/api`:

- `GET /api/health` - service health and version metadata
- `GET /api/system` - full system snapshot (host/OS, CPU, memory, swap, disk list, RAID, physical disks, network, specs)
- `GET /api/gpu` - live NVIDIA GPU metrics (or unavailable reason)
- `GET /api/docker` - Docker container inventory (or unavailable reason)
- `GET /api/summary` - compact dashboard KPIs

Interactive docs:

- `http://localhost:4040/api/docs`

## Quick Start (Development)

### Prerequisites

- Python 3.11+
- Node.js 20+ and npm
- Linux host for full hardware/RAID temperature fidelity
- Optional for extended telemetry:
  - Docker daemon access
  - NVIDIA drivers + NVML
  - `smartctl` and `dmidecode`

### 1) Run Backend

```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\python.exe -m ensurepip --upgrade
.\.venv\Scripts\python.exe -m pip install --upgrade pip
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\.venv\Scripts\python.exe run.py
```

Default backend URL: `http://localhost:4040`

### 2) Run Frontend

Open another terminal:

```powershell
cd frontend
npm.cmd install
npm.cmd start
```

Default frontend URL: `http://localhost:4041`

In development, frontend requests to `/api/*` are proxied to `http://127.0.0.1:4040` via `frontend/proxy.conf.json`.

### 3) Run Discord Bot (Optional)

```powershell
cd bot
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install --upgrade pip
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
Copy-Item .env.example .env
# fill .env values
.\.venv\Scripts\python.exe src\bot.py
```

## Configuration

### Backend (`backend/.env`)

Key variables:

- `API_PREFIX` (default `/api`)
- `HOST` (default `0.0.0.0`)
- `PORT` (default `4040`)
- `CORS_ORIGINS` (default `http://localhost:4041,http://127.0.0.1:4041`)
- `CORS_ORIGIN_REGEX` (optional)
- `DISK_MOUNTPOINT` (default `/`)
- `DOCKER_TIMEOUT_SECONDS` (default `3`)

### Frontend (`frontend/src/environments/environment.shared.ts`)

- `backendBaseUrl` (default empty for same-origin)
- `apiPrefix` (default `/api`)
- `polling.summaryMs` (default `5000`)
- `polling.detailsMs` (default `5000`)
- `polling.healthMs` (default `15000`)

### Bot (`bot/.env`)

- `DISCORD_BOT_TOKEN` (required)
- `DISCORD_CHANNEL_ID` (required)
- `MONITOR_API_BASE_URL` (required, example `http://127.0.0.1:4040`)
- `POLL_INTERVAL_SECONDS` (default `30`)
- `ALERT_GRACE_SECONDS` (default `300` for all alerts)
- Thresholds: CPU/memory/disk/GPU temp
- Feature flags: `ENABLE_DOCKER_ALERTS`, `ENABLE_RAID_ALERTS`

Legacy fallback: `ENDPOINT_ALERT_GRACE_SECONDS` is still recognized when `ALERT_GRACE_SECONDS` is unset.

## Production Shape

Recommended deployment pattern:

1. Build frontend: `cd frontend && npm run build`
2. Serve frontend static assets + reverse proxy `/api` to backend (`127.0.0.1:4040`)
3. Keep backend non-public if proxying from same host
4. Restrict CORS to known origins if cross-origin access is needed
5. Run Discord bot as a separate process/service

## Testing

Backend:

```powershell
cd backend
.\.venv\Scripts\python.exe -m pytest -v
```

Bot:

```powershell
cd bot
python -m unittest discover tests -v
```

Frontend:

```powershell
cd frontend
npm.cmd run test:unit
```

## Detailed Documentation

For deeper implementation and architecture details, see:

- [`docs/EXTENSIVE_DOCUMENTATION.md`](docs/EXTENSIVE_DOCUMENTATION.md)
- [`backend/README.md`](backend/README.md)
- [`frontend/README.md`](frontend/README.md)
- [`bot/README.md`](bot/README.md)
