# linux-monitor frontend (Angular)

Read-only homelab dashboard for the FastAPI monitoring backend.

## Features

- Dark-theme dashboard with summary cards and detail panels
- Polling-based data refresh (no WebSockets)
- Graceful handling of unavailable GPU/Docker telemetry
- Environment-based API base URL and prefix configuration
- Compact, expandable Angular architecture (core/services/models/shared components)

## Project structure

```text
frontend/
  src/
    app/
      core/
        models/
        pipes/
        services/
        utils/
      features/
        dashboard/
          pages/
      shared/
        components/
    environments/
```

## Install dependencies

```bash
cd frontend
npm install
```

PowerShell (if script execution policy blocks `npm`):

```powershell
cd Frontend
npm.cmd install
```

## Configure backend API URL and prefix

Environment files:

- `src/environments/environment.ts` (production build defaults)
- `src/environments/environment.development.ts` (dev server)

Config keys:

- `backendBaseUrl`: host + port of backend, e.g. `http://localhost:8000`
  - Use `''` with Angular proxy for local development.
- `apiPrefix`: backend API prefix (default `/api`)
- `polling.summaryMs`: summary polling interval
- `polling.detailsMs`: system/gpu/docker polling interval
- `polling.healthMs`: health polling interval

Default setup in this project assumes:

- `backendBaseUrl = ''`
- `apiPrefix = '/api'`

and uses `proxy.conf.json` so `/api/*` is proxied to `http://127.0.0.1:8000`.

If your FastAPI backend runs on `http://localhost:8000`, either:

1. keep the default proxy target (`http://127.0.0.1:8000`), or
2. set `backendBaseUrl` to `http://127.0.0.1:8000` and run without proxy.

## Run dev server

```bash
npm start
```

PowerShell:

```powershell
npm.cmd start
```

App URL:

- `http://localhost:4200`

## Build for production

```bash
npm run build
```

Build output:

- `dist/linux-monitoring-ui`

## Backend contract used by this frontend

The frontend reads only these endpoints:

- `GET /api/health`
- `GET /api/system`
- `GET /api/gpu`
- `GET /api/docker`
- `GET /api/summary`

No write/admin/control actions are implemented.

## Notes about response shape assumptions

This frontend aligns with the FastAPI models you described and also tolerates minor shape variants:

- `system.os` object is preferred; fallback `system.platform` is supported.
- `cpu.load_average` supports object form (`one_min`, `five_min`, `fifteen_min`) and array form (`[1,5,15]`).
- `docker.containers[].ports` supports object map form and string form.

Unavailable subsystem behavior:

- GPU unavailable: section renders a non-fatal unavailable state with backend reason.
- Docker unavailable: section renders a non-fatal unavailable state with backend reason.

If one endpoint fails, other sections continue rendering with their latest successful data.
