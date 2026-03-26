# Linux Monitoring: Extensive Documentation

## 1. Project Overview

`linux-monitoring` is a three-service monorepo for read-only infrastructure monitoring:

- **Backend (`backend/`)**: FastAPI service that collects and normalizes telemetry.
- **Frontend (`frontend/`)**: Angular dashboard that polls backend endpoints and renders operator-friendly views.
- **Discord Bot (`bot/`)**: Discord slash-command and alerting service that consumes the same API contract.

The design goal is operational visibility without control-plane risk: no write endpoints, no remote mutation operations.

## 2. End-to-End Architecture

```text
                        +-------------------------------+
                        |        Linux Host             |
                        | /proc, /sys, psutil, Docker,  |
                        | NVML, smartctl, dmidecode     |
                        +---------------+---------------+
                                        |
                                        v
+-------------------------+   GET   +-------------------------+
| Angular Frontend        +-------->+ FastAPI Backend         |
| `frontend`              |         | `backend/app`           |
| port 4041 (dev)         |         | port 4040 (default)     |
+-------------------------+         +-------------------------+
                                        ^
                                        |
+-------------------------+   GET       |
| Discord Bot             +-------------+
| `bot/src/bot.py`        |
+-------------------------+
```

### 2.1 Process Boundaries

- Frontend and bot are independent clients.
- Backend is the only telemetry collector.
- Bot intentionally does not duplicate metric collection logic.

### 2.2 API Surface

All endpoints are mounted under `API_PREFIX` (default `/api`):

- `GET /health`
- `GET /system`
- `GET /gpu`
- `GET /docker`
- `GET /summary`

OpenAPI and docs:

- `/api/openapi.json`
- `/api/docs`
- `/api/redoc`

## 3. Backend Deep Dive (`backend/`)

## 3.1 Runtime Entry and App Wiring

- Entry script: `backend/run.py`
- App factory module: `backend/app/main.py`

Startup flow:

1. `get_settings()` loads `.env` and parses typed settings.
2. Logging is initialized with configured log level.
3. FastAPI app is created with docs paths under configured API prefix.
4. CORS middleware is applied.
5. API routers are attached.
6. Startup/shutdown events log lifecycle messages.

Global exception behavior:

- Unhandled exceptions are logged server-side.
- API response is redacted to `500 {"detail": "Internal server error"}`.

## 3.2 Backend Module Responsibilities

### 3.2.1 `app/core/`

- `config.py`: env parsing and defaults, cached settings object.
- `logging.py`: centralized logging formatter/level setup.
- `utils.py`: UTC helpers, duration formatting, Docker timestamp parsing.

### 3.2.2 `app/api/`

- `router.py`: composes endpoint routers.
- `routes/*.py`: thin HTTP handlers delegating to services.

### 3.2.3 `app/models/`

Pydantic models define API contracts and constraints:

- `health.py`: `HealthResponse`
- `summary.py`: `SummaryResponse`
- `system.py`: rich nested schema (CPU/memory/disks/RAID/specs/network)
- `gpu.py`: `GPUResponse`
- `docker.py`: Docker container and summary responses

### 3.2.4 `app/services/`

- `summary_service.py`: compact KPIs for dashboard cards.
- `gpu_service.py`: NVML-backed GPU metrics/static specs.
- `docker_service.py`: Docker SDK container discovery + formatting.
- `system/service.py`: aggregate full system response.
- `system/base_metrics.py`: hostname, CPU/memory/swap/disk basics.
- `system/specs_metrics.py`: static hardware inventory (CPU flags, memory modules, motherboard, static GPU specs).
- `system/storage_metrics.py`: mounted disks, RAID arrays, physical disks, disk temperature probing and health states.
- `system/network_metrics.py`: traffic counters and top link speed.
- `system/temperature_metrics.py`: CPU/chassis sensor extraction from psutil and sysfs.

## 3.3 Configuration Model

`backend/.env.example` keys:

- `APP_NAME`, `APP_VERSION`
- `API_PREFIX`
- `CORS_ORIGINS`, `CORS_ORIGIN_REGEX`
- `DISK_MOUNTPOINT`
- `LOG_LEVEL`
- `HOST`, `PORT`, `RELOAD`
- `DOCKER_TIMEOUT_SECONDS`

Validation/parsing behavior:

- Integer env values clamp to minimums.
- Boolean parser accepts: `1,true,yes,on`.
- Empty optional strings normalize to `None`.
- Settings are cached (`lru_cache`) for runtime efficiency.

## 3.4 Endpoint Semantics

### 3.4.1 `GET /health`

Returns service metadata only:

- `status` (`ok`)
- `app_name`
- `version`
- `timestamp` (UTC)

### 3.4.2 `GET /summary`

Purpose:

- Fast, compact status for top cards and alert thresholds.

Fields include:

- host + uptime
- CPU/memory/disk percentages
- GPU availability + temp/utilization when available
- Docker availability + running container count

### 3.4.3 `GET /system`

Purpose:

- Full snapshot used by deep dashboard panels and storage/RAID alert logic.

Major payload sections:

- host and OS metadata
- static hardware `specs` (CPU/memory/motherboard/GPU metadata)
- runtime CPU/memory/swap/disk/network
- `disks`: mounted filesystems with health
- `raid_arrays`: Linux MD array health/status
- `physical_disks`: hardware disk inventory with kernel-state-derived health

### 3.4.4 `GET /gpu`

- Attempts NVML initialization.
- Reports unavailable state with reason when NVML/GPU is missing.
- Returns temperature, utilization, memory, power, fan speed, driver when available.

### 3.4.5 `GET /docker`

- Attempts Docker client creation with configurable timeout.
- Returns `docker_available=false` with reason on access/connect failures.
- Includes container list (name, image, state, status, created, runtime, mapped ports).

## 3.5 Fault Tolerance and Graceful Degradation

Backend is built to continue serving partial data.

Patterns used:

- Optional dependencies (`docker`, `pynvml`, `psutil`) guarded at import/runtime.
- Read failures map to safe defaults (`0`, `null`, unavailable flags).
- Unavailable subsystems do not crash unrelated endpoints.
- Unexpected exception messages are redacted in API responses.

Examples:

- Docker socket permission issue -> `docker_available=false`, reason `Docker access denied.`
- Missing NVML -> GPU endpoint returns unavailable without stack leak.
- Disk mountpoint read failure -> fallback mountpoint and safe zeroed metrics when needed.

## 3.6 Linux-Specific Behavior and Tooling

Rich telemetry depends on Linux interfaces/tools:

- `/proc/cpuinfo` for model/vendor/capabilities
- `/sys/class/dmi` for motherboard metadata
- `/sys/block` for RAID and physical disk topology
- `smartctl` (preferred) for disk temperatures
- `dmidecode` (optional) for RAM module inventory

Cross-platform handling:

- Windows paths return minimal/fallback values for Linux-only sections.
- Non-Linux systems still receive valid API responses with reduced detail.

## 3.7 Storage Health Model

Disk health states (`healthy`, `warning`, `critical`, `unknown`) are computed from:

- usage thresholds (>=85 warning, >=95 critical)
- read-only state
- metric availability

RAID health states combine:

- degraded member counts
- array state (`inactive`, `suspended`, etc.)
- active sync actions (resync/recovery)

Physical disk health combines:

- kernel-reported state
- size validity
- membership in degraded/syncing RAID arrays

## 4. Frontend Deep Dive (`frontend/`)

## 4.1 Frontend Architecture

- Angular standalone app (`main.ts` + `app.config.ts`)
- Router routes root path to dashboard page component
- Core layer:
  - API models (`core/models`)
  - API service (`core/services/monitoring-api.service.ts`)
  - facade (`core/services/dashboard-facade.service.ts`)
  - pipes and formatting utilities
- Feature layer:
  - dashboard page and feature panels
- Shared layer:
  - reusable UI components (metric cards, progress bars, status badges, section wrappers)

## 4.2 Polling and State Orchestration

`DashboardFacadeService` is the state brain.

Mechanics:

- Each resource (`summary/system/gpu/docker/health`) is represented as a `ResourceState<T>` stream.
- Polling is interval-driven via `timer(0, intervalMs)`.
- Failed requests keep prior data while updating error state.
- Streams are `shareReplay`'d to avoid duplicate network requests across subscribers.

Dynamic polling intervals:

- Summary interval is user-adjustable (clamped between `500ms` and `1h`).
- Details interval = `max(summaryInterval * 5, environment.polling.detailsMs)`.
- Health interval = `max(summaryInterval * 10, environment.polling.healthMs)`.

This allows near-real-time summary cards while reducing load for heavy endpoints.

## 4.3 API URL Strategy

`buildApiUrl()` composes URLs from:

- `backendBaseUrl` (empty by default for same-origin)
- `apiPrefix` (default `/api`)
- endpoint path

Development mode uses `proxy.conf.json` to route `/api` to backend `127.0.0.1:4040`.

## 4.4 Dashboard UX and Data Compatibility

The dashboard supports minor backend shape variants for resilience:

- `system.os` preferred, fallback to legacy `platform` field.
- load average supports both object and tuple array forms.
- Docker ports support object map or legacy string form.

UI sections:

- top summary cards
- system detail panels
- disk/RAID/physical disk tables
- Docker panel with running/stopped/image KPIs
- health status panel

## 4.5 Formatting Logic Highlights

`format.utils.ts` includes:

- byte and MB conversion helpers
- optional value normalization (`N/A` fallback)
- load-average normalization
- Docker ports compaction (range compression + concise display)
- threshold-based tone mapping (`good`, `warn`, `bad`, `neutral`)

## 5. Discord Bot Deep Dive (`bot/`)

## 5.1 Runtime Model

Main class: `MonitoringDiscordBot` (`bot/src/bot.py`).

Responsibilities:

- Register slash commands
- Poll backend for alerting
- Post scheduled status updates
- Persist alert and schedule state

## 5.2 Slash Commands

Core commands:

- `/status`
- `/health`
- `/docker`
- `/gpu`
- `/system`

Scheduling commands:

- `/status_schedule <interval_minutes>`
- `/status_schedule_custom <windows_spec>`
- `/status_schedule_off`
- `/status_schedule_show`

Permission rules:

- schedule-modifying commands require `Manage Server` (or owner/admin)
- optional guild lock via `DISCORD_GUILD_ID`

## 5.3 Alert Polling Pipeline

Loop: `alert_polling` (interval from `POLL_INTERVAL_SECONDS`).

Pipeline:

1. Fetch `/api/health`.
2. If health fetch fails, emit backend-unavailable alert.
3. Otherwise fetch `/summary`, `/system`, `/gpu`, `/docker` concurrently.
4. Build alert set via `evaluate_alerts()`.
5. Deduplicate via `AlertState.transition()`.
6. Send new alerts and recovery messages.
7. Persist active alert snapshot atomically.

Alert categories:

- backend/endpoint availability
- CPU and memory thresholds (from summary)
- disk usage threshold (from system disks)
- disk/physical disk/RAID health statuses
- GPU temperature threshold
- Docker availability

## 5.4 Alert Deduplication and Recovery

`AlertState` tracks active alerts by stable `key`.

- New key -> sends alert once.
- Existing key with changed message/severity -> updates state silently (no duplicate alert spam).
- Missing formerly-active key -> sends recovery message with active duration.

Snapshots store:

- key/title/message/severity
- first_seen / last_seen timestamps

## 5.5 Scheduled Status Engine

Second loop: `status_autopost` runs every 30 seconds.

Scheduling modes:

- `fixed`: post every N minutes
- `windows`: post only in configured windows, each with its own interval

Custom windows grammar:

`HH:MM-HH:MM=MINUTES;HH:MM-HH:MM=MINUTES;...`

Example:

`12:00-15:00=15;15:00-18:00=60;21:00-06:00=360`

Rules enforced:

- no overlapping windows
- min/max interval bounds
- wrap-around windows allowed (cross midnight)

State persistence:

- schedule config persisted to JSON file (atomic temp-file replace)
- loaded on startup and validated

## 5.6 Bot Configuration

`BotConfig.from_env()` validates and types all env values:

- required secrets/IDs
- numeric interval/threshold bounds
- boolean feature flags
- state-file path resolution (relative paths resolved inside `bot/`)

## 6. Data Contracts and Compatibility Notes

## 6.1 Backend -> Frontend/Bot Contract

Critical assumptions consumed by both clients:

- `/summary` percentages are numeric and normalized
- `/system.disks` entries include availability and health objects
- `/gpu.available` and `/docker.docker_available` gate optional sections
- health statuses use `healthy|warning|critical|unknown`

## 6.2 Backward Compatibility Hooks in Frontend

Frontend still supports:

- legacy `system.platform`
- load average array format
- legacy Docker ports string format

This reduces breakage during backend schema transitions.

## 7. Security, Safety, and Operational Constraints

## 7.1 Read-Only API Surface

- FastAPI CORS allows only `GET` and `OPTIONS`.
- No mutating endpoints are exposed.

## 7.2 Error Redaction

Backend intentionally avoids leaking sensitive runtime details in public API error messages.

Validated by tests:

- Docker errors do not expose socket paths
- GPU errors do not expose device/library internals

## 7.3 Permission Boundaries

- Docker metrics require daemon socket access.
- GPU metrics require NVIDIA driver + NVML access.
- Some hardware details require elevated host permissions (`dmidecode`, `smartctl`).

## 8. Testing Strategy and Coverage Map

## 8.1 Backend Tests (`backend/tests`)

Covers:

- endpoint contracts and docs exposure
- config parsing behavior
- redaction on unexpected exceptions
- temperature parsing helpers
- temperature source preference logic

## 8.2 Bot Tests (`bot/tests`)

Covers:

- env config parsing and validation
- alert dedupe + recovery transitions
- schedule parsing/serialization
- next-event computation for fixed and window modes

## 8.3 Frontend Tests (`frontend/src/**/*.spec.ts`)

Covers:

- app bootstrap sanity
- API URL building
- API service endpoint usage
- formatting utilities (load average, Docker ports, usage tones)

## 9. Deployment Patterns

## 9.1 Recommended Production Topology

- Reverse proxy serves frontend static files.
- Reverse proxy routes `/api` to backend on loopback.
- Backend runs non-public when possible.
- Discord bot runs as separate service with outbound HTTPS to backend/Discord.

## 9.2 Suggested Serviceization

- `backend`: systemd or container with host telemetry access
- `frontend`: static server or CDN with reverse proxy rules
- `bot`: long-running service with restart policy

## 10. Extension Guide

Common extension points:

- Add backend metric:
  1. implement service collector
  2. add model fields
  3. expose through route response
  4. update frontend model + panel rendering
  5. optionally add bot formatter/alert rule

- Add new alert policy:
  1. implement rule in `alert_rules.py`
  2. use stable key naming for dedupe
  3. add tests for alert and recovery behavior

- Add dashboard module:
  1. add API model fields
  2. consume in facade stream
  3. render in feature component
  4. preserve graceful fallback states

## 11. Known Constraints and Improvement Opportunities

Current constraints:

- frontend uses polling, not streaming
- hardware fidelity is highest on Linux hosts
- bot depends on backend reachability

Potential improvements:

- optional push channel (SSE/WebSocket) for near-real-time updates
- auth layer for non-private deployments
- persisted historical metrics for trends/anomaly detection
- explicit API versioning for long-term contract stability

## 12. File Reference Quick Index

Backend:

- `backend/run.py`
- `backend/app/main.py`
- `backend/app/core/config.py`
- `backend/app/api/routes/*.py`
- `backend/app/services/system/*.py`

Frontend:

- `frontend/src/app/core/services/dashboard-facade.service.ts`
- `frontend/src/app/core/services/monitoring-api.service.ts`
- `frontend/src/app/features/dashboard/pages/dashboard-page.component.*`
- `frontend/src/app/features/dashboard/components/*`

Bot:

- `bot/src/bot.py`
- `bot/src/alert_rules.py`
- `bot/src/alert_state.py`
- `bot/src/schedule_policy.py`
- `bot/src/config.py`
