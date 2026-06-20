# Linux Monitoring

Linux homelab monitoring monorepo with a FastAPI monitoring backend, Angular
dashboard, Discord bot, restricted control agent, and Flutter Android tablet
cockpit.

## Current Stack

- `backend/`: FastAPI telemetry API, historical metrics, backend-owned alert
  evaluation, and Firebase Cloud Messaging delivery for the tablet.
- `frontend/`: read-only Angular dashboard for the monitoring backend.
- `bot/`: Discord slash-command and alert-event presentation client.
- `control_agent/`: restricted privileged API for Wake-on-LAN, managed hosts,
  Tailscale-aware device state, and allowlisted service controls.
- `mobile/`: Android-only Flutter tablet app with monitoring pages, SSH
  terminal, restricted SFTP file browser, service dashboard, widgets, and push
  alert registration.

Most telemetry endpoints are read-only. Mobile-alert registration and test
routes are scoped to the monitoring backend with a dedicated mobile-alert
token. Privileged actions stay isolated in the control agent.

## Architecture

```text
Angular frontend                 Discord bot
frontend/ :4041                  bot/
       | GET /api/*                 | GET /api/alerts/*
       v                            v
+--------------------------------------------------+
| FastAPI monitoring backend                       |
| backend/ :4040/api                               |
| telemetry, history, alerts, mobile FCM delivery  |
+--------------------------------------------------+
       ^
       | GET telemetry/history, POST mobile-alert registration
       |
Flutter Android tablet
mobile/
       |
       | privileged actions only
       v
+--------------------------------------------------+
| FastAPI control agent                            |
| control_agent/ :4042/api                         |
| Wake-on-LAN, hosts, devices, services            |
+--------------------------------------------------+
```

The production tablet deployment is expected to communicate over Tailscale or a
private reverse-proxy boundary. The live testing URLs are:

```text
Monitoring API: http://100.64.10.22:4040/api
Control API:    http://100.64.10.22:4042/api
```

## Backend API

Monitoring backend endpoints under `/api`:

- `GET /health`
- `GET /system`
- `GET /gpu`
- `GET /docker`
- `GET /summary`
- `GET /history/ranges`
- `GET /history/overview`
- `GET /history/storage`
- `GET /history/disks`
- `GET /history/raid`
- `GET /alerts/events`
- `GET /alerts/active`
- `GET /alerts/status`
- `GET /mobile-alerts/status`
- `POST /mobile-alerts/register`
- `DELETE /mobile-alerts/register/{installation_id}`
- `POST /mobile-alerts/test`

Control-agent endpoints under `/api`:

- `GET /health`
- `GET /devices`
- `GET /hosts`
- `GET /hosts/{host_id}`
- `GET /services`
- `GET /services/{service_id}`
- `POST /services/{service_id}/actions/{action}`
- `POST /actions/wake-main-pc`

The old server-side neighbor inventory endpoint has been removed from the
default control-agent API. Device inventory now comes from configured devices
and Tailscale peer state.

## Mobile App

The Flutter app is tablet-first and Android-only. Current routes include:

```text
/overview
/hardware
/storage
/gpu
/network
/history
/hosts
/hosts/:hostId
/devices
/devices/:deviceId
/actions
/terminal
/files
/services
/services/:serviceId
/settings
```

Notable current behavior:

- Overview status chips and metric cards route to the relevant pages.
- Network focuses on traffic and history ranges, not LAN scanning.
- Devices shows configured devices plus Tailscale peers, with duplicate merge
  behavior in the control agent.
- Hosts shows managed hosts and useful host actions.
- Services shows configured allowlisted services and a service detail dashboard.
- Files uses direct restricted SFTP with configurable background disconnect
  timing and capped previews.
- GPU numbers stay neutral; utilization and VRAM bars carry threshold color.
- Hardware and Storage apply shared threshold colors for values where higher is
  worse.
- Android widgets store non-sensitive flattened telemetry only.

## Quick Start

Backend:

```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\python.exe -m ensurepip --upgrade
.\.venv\Scripts\python.exe -m pip install --upgrade pip
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\.venv\Scripts\python.exe run.py
```

Control agent:

```powershell
cd control_agent
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install --upgrade pip
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\.venv\Scripts\python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 4042
```

Mobile:

```powershell
cd mobile
flutter pub get
flutter analyze
flutter test
flutter run
```

Frontend:

```powershell
cd frontend
npm.cmd install
npm.cmd start
```

Bot:

```powershell
cd bot
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install --upgrade pip
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
Copy-Item .env.example .env
.\.venv\Scripts\python.exe src\bot.py
```

## Configuration Highlights

Backend:

- `DISK_MOUNTPOINT=/`
- `VISIBLE_MOUNTPOINTS=/,/mnt/storage,/mnt/warm` to allow only specific mounts
- `IGNORED_MOUNT_PREFIXES_EXTRA=/srv/sftp` to hide bind-mount trees
- `HISTORY_*` for SQLite history collection
- `ALERT_*`, `MOBILE_PUSH_*`, `MOBILE_ALERT_API_TOKEN`, and
  `ALERT_CONSUMER_API_TOKEN` for backend-owned alert delivery

Control agent:

- `CONTROL_API_TOKEN`
- `KNOWN_DEVICES_CONFIG_PATH`
- `MANAGED_HOSTS_CONFIG_PATH`
- `SERVICES_CONFIG_PATH`
- `SERVICE_CONTROL_HELPER_PATH`
- `MAIN_PC_MAC`, `WAKE_BROADCAST_HOST`, `WAKE_PORT`

Mobile:

- Monitoring API URL and Control API URL are stored on-device.
- SSH/SFTP private keys and passphrases are stored through secure storage.
- SFTP background timeout is configurable in Settings.
- Widget refresh interval is limited to 15, 30, or 60 minutes.

## Verification

Run before shipping changes:

```powershell
cd mobile
flutter pub get
flutter analyze
flutter test

cd ..\control_agent
python -m pytest

cd ..\backend
python -m pytest
```

Core backend/control-agent/mobile checks can also be run without touching the
Angular frontend:

```bash
./scripts/check-core.sh
```

Additional checks when those areas change:

```powershell
cd frontend
npm.cmd test
npm.cmd run build

cd ..\bot
python -m unittest discover tests -v
```

## Documentation Map

- [`backend/README.md`](backend/README.md)
- [`control_agent/README.md`](control_agent/README.md)
- [`mobile/README.md`](mobile/README.md)
- [`frontend/README.md`](frontend/README.md)
- [`bot/README.md`](bot/README.md)
- [`docs/EXTENSIVE_DOCUMENTATION.md`](docs/EXTENSIVE_DOCUMENTATION.md)
- [`docs/MOBILE_APP_ARCHITECTURE.md`](docs/MOBILE_APP_ARCHITECTURE.md)
- [`docs/HISTORICAL_METRICS.md`](docs/HISTORICAL_METRICS.md)
- [`docs/BACKEND_OWNED_MOBILE_ALERTS.md`](docs/BACKEND_OWNED_MOBILE_ALERTS.md)
- [`docs/ANDROID_WIDGETS_AND_PUSH_ALERTS.md`](docs/ANDROID_WIDGETS_AND_PUSH_ALERTS.md)
- [`docs/ANDROID_WIDGETS.md`](docs/ANDROID_WIDGETS.md)
- [`docs/SERVICE_CONTROLS.md`](docs/SERVICE_CONTROLS.md)
- [`docs/MANAGED_HOSTS.md`](docs/MANAGED_HOSTS.md)
- [`docs/KNOWN_DEVICES_CONFIG.md`](docs/KNOWN_DEVICES_CONFIG.md)
- [`docs/CONTROL_AGENT_DEPLOYMENT.md`](docs/CONTROL_AGENT_DEPLOYMENT.md)
- [`docs/HOMELAB_HOST_PROBE_DEPLOYMENT_NOTE.md`](docs/HOMELAB_HOST_PROBE_DEPLOYMENT_NOTE.md)
- [`docs/RESTRICTED_SFTP_SETUP.md`](docs/RESTRICTED_SFTP_SETUP.md)
- [`docs/FILE_EXPLORER_ADVANCED.md`](docs/FILE_EXPLORER_ADVANCED.md)
- [`docs/ANDROID_RELEASE_GUIDE.md`](docs/ANDROID_RELEASE_GUIDE.md)
- [`docs/EXPANSION_DEPLOYMENT_CHECKLIST.md`](docs/EXPANSION_DEPLOYMENT_CHECKLIST.md)
- [`docs/EXPANSION_AUDIT.md`](docs/EXPANSION_AUDIT.md)
