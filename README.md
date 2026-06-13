# Linux Monitoring

Linux homelab monitoring monorepo with a FastAPI monitoring backend, Angular dashboard, Discord bot, restricted control agent, and Flutter tablet app.

Homelab monitoring stack built as a monorepo:

- `backend/`: FastAPI monitoring API, history collector, alert engine, FCM mobile delivery
- `frontend/`: Angular dashboard UI
- `bot/`: Discord bot for slash commands, backend alert-event presentation, and scheduled status posts
- `control_agent/`: restricted privileged homelab actions
- `mobile/`: Flutter Android tablet app and widgets

## Why This Project

This project gives you one monitoring pipeline for local servers:

- **System telemetry**: CPU, memory, swap, uptime, disks, network, temperatures
- **Storage health context**: mounted disks, RAID arrays, physical disk inventory and health summaries
- **GPU telemetry**: NVIDIA metrics through NVML (when available)
- **Docker telemetry**: container inventory and runtime status (when available)
- **Backend-owned alerts**: sustained threshold evaluation, immutable alert events, FCM delivery, and retry outbox
- **Discord integration**: chat-accessible status and backend alert-event presentation
- **Tablet control**: direct monitoring API use plus separate privileged-control API use where needed

Most telemetry endpoints are read-only. Mobile-alert registration/test routes are scoped to the monitoring backend with a dedicated mobile-alert token. Privileged actions are isolated in the control agent.

## Architecture

```text
+---------------------+          +-----------------------+
| Angular Frontend    |  GET     | FastAPI Backend       |
| :4041               +--------->+ :4040/api/*           |
| (polling dashboard) |          | telemetry/history     |
+----------+----------+          +-----+-----------------+
           |                           |
           |                           |
           |                           +--> alert engine + alerts.sqlite3
           |                           +--> Firebase Admin FCM sender
           |                           +--> psutil (CPU/RAM/disk/net)
           |                           +--> Linux sysfs (/sys, /proc)
           |                           +--> smartctl (optional disk temps)
           |                           +--> Docker SDK (optional)
           |                           +--> NVML (optional NVIDIA)
           |
           | alert event feed + slash commands
           v
+---------------------+      GET      +-----------------------+
| Discord Bot         +-------------->+ FastAPI Backend       |
| (discord.py)        |               | :4040/api/alerts/*    |
+---------------------+               +-----------------------+

+---------------------+      POST     +-----------------------+
| Flutter Tablet      +-------------->+ FastAPI Backend       |
| mobile alerts       |               | :4040/api/mobile-*    |
+----------+----------+               +-----------------------+
           |
           | privileged actions only
           v
+---------------------+
| Control Agent       |
| :4042/api/*         |
+---------------------+
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
  control_agent/
    app/
    config/
    tests/
  frontend/
    src/app/
      core/
      features/dashboard/
      shared/
    proxy.conf.json
  bot/
    src/
    tests/
  mobile/
    lib/
    android/
    test/
```

## API Endpoints

Backend exposes these endpoints under `/api`:

- `GET /api/health` - service health and version metadata
- `GET /api/system` - full system snapshot (host/OS, CPU, memory, swap, disk list, RAID, physical disks, network, specs)
- `GET /api/gpu` - live NVIDIA GPU metrics (or unavailable reason)
- `GET /api/docker` - Docker container inventory (or unavailable reason)
- `GET /api/summary` - compact dashboard KPIs
- `GET /api/history/*` - historical metrics
- `GET /api/alerts/events` - scoped alert event feed for consumers
- `GET /api/alerts/active` - scoped active backend alerts
- `GET /api/alerts/status` - scoped alert engine status
- `GET /api/mobile-alerts/status` - scoped tablet registration status
- `POST /api/mobile-alerts/register` - scoped tablet FCM registration
- `DELETE /api/mobile-alerts/register/{installation_id}` - scoped tablet disable/unregister
- `POST /api/mobile-alerts/test` - scoped backend-to-FCM round-trip test

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
- `HISTORY_DB_PATH` (default `/var/lib/linux-monitoring/history.sqlite3`)
- `ALERTS_ENABLED` (default `true`)
- `ALERT_DB_PATH` (default `/var/lib/linux-monitoring/alerts.sqlite3`)
- `ALERT_GRACE_SECONDS` (default `300`)
- `MOBILE_PUSH_ENABLED` (default `false`)
- `FIREBASE_SERVICE_ACCOUNT_FILE` (default `/etc/linux-monitor-mobile-alerts/firebase-service-account.json`)
- `MOBILE_ALERT_API_TOKEN` (dedicated tablet registration/test token)
- `ALERT_CONSUMER_API_TOKEN` (dedicated Discord/event-consumer token)

### Frontend (`frontend/src/environments/environment.shared.ts`)

- `backendBaseUrl` (default empty for same-origin)
- `apiPrefix` (default `/api`)
- `polling.summaryMs` (default `5000`)
- `polling.detailsMs` (default `5000`)
- `polling.healthMs` (default `15000`)

### Bot (`bot/.env`)

- `DISCORD_BOT_TOKEN` (required)
- `DISCORD_CHANNEL_ID` (required)
- `MONITORING_API_BASE_URL` (required, example `http://127.0.0.1:4040/api`)
- `ALERT_CONSUMER_API_TOKEN` (required, matches backend)
- `DISCORD_ALERT_CURSOR_FILE` (default `/var/lib/linux-monitoring/discord_alert_cursor.json`)
- `DISCORD_ALERT_REPLAY_ON_FIRST_START` (default `false`)
- `POLL_INTERVAL_SECONDS` (default `30`)

## Production Shape

Recommended deployment pattern:

1. Build frontend: `cd frontend && npm run build`
2. Serve frontend static assets + reverse proxy `/api` to backend (`127.0.0.1:4040`)
3. Keep backend non-public if proxying from same host
4. Restrict CORS to known origins if cross-origin access is needed
5. Run Discord bot as a separate event-consumer process/service
6. Run control agent separately on `:4042` for privileged actions only

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
npm.cmd test
```

## Detailed Documentation

For deeper implementation and architecture details, see:

- [`docs/EXTENSIVE_DOCUMENTATION.md`](docs/EXTENSIVE_DOCUMENTATION.md)
- [`backend/README.md`](backend/README.md)
- [`frontend/README.md`](frontend/README.md)
- [`bot/README.md`](bot/README.md)
- [`control_agent/README.md`](control_agent/README.md)
- [`docs/BACKEND_OWNED_MOBILE_ALERTS.md`](docs/BACKEND_OWNED_MOBILE_ALERTS.md)
