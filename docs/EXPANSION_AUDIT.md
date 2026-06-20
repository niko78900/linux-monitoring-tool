# Expansion Audit

Date: 2026-06-11
Branch audited: `codex/mobile-architecture-phase-0`
Working tree state at audit time: clean

Current update: this document is a historical Phase A audit. It intentionally
describes the repository as it existed on 2026-06-11. Since then, the repo has
added backend history, backend-owned mobile alerts, Android widgets, managed
hosts, service controls, Tailscale-aware devices, richer file previews, SFTP
background timeout, and storage mount filtering. Use the root `README.md` and
focused docs for current operational behavior.

## Scope

This document audits the actual local repository before any Expansion Pack work beyond Phase A.

The audit covered:

- `backend/app/`
- `backend/tests/`
- `mobile/lib/`
- `mobile/android/`
- `mobile/test/`
- `control_agent/app/`
- `control_agent/tests/`
- `docs/`
- root deployment notes and scripts

No later phases were implemented during this audit.

## Executive Summary

The local repository already contains:

- a read-only FastAPI monitoring backend under `backend/`
- a separate restricted FastAPI control agent under `control_agent/`
- an Android-only Flutter tablet app under `mobile/`
- a restricted SSH terminal and restricted SFTP browser in the mobile app
- a fixed allowlisted Wake-on-LAN action for Main PC
- a known-devices dashboard backed by YAML plus an audit-time optional neighbor concept

At audit time, the codebase did **not** yet contain:

- persistent historical metrics storage
- history API endpoints
- a managed-host scaffold separate from the current known-device model
- Jellyfin or HFS service-control code
- advanced file-browser metadata storage, previews, uploads, or resumable transfers
- Android home-screen widget code

Repository evidence for Jellyfin and HFS runtime details is currently absent. Those runtime details are **not verified** by the local repo.

## Current Architecture

### Monitoring backend

Current backend shape:

- Framework: FastAPI
- API prefix: `/api`
- Default port: `4040`
- Allowed methods: `GET`, `OPTIONS`
- Purpose: read-only monitoring only

Key files:

- `backend/app/main.py`
- `backend/app/api/router.py`
- `backend/app/api/routes/health.py`
- `backend/app/api/routes/system.py`
- `backend/app/api/routes/gpu.py`
- `backend/app/api/routes/docker.py`
- `backend/app/api/routes/summary.py`
- `backend/app/services/system/`
- `backend/app/services/gpu_service.py`
- `backend/app/services/docker_service.py`
- `backend/app/services/summary_service.py`

Behavior:

- `/api/system` aggregates system, disk, RAID, physical disk, and network details.
- `/api/gpu` exposes optional NVIDIA telemetry.
- `/api/docker` exposes container inventory through Docker SDK when available.
- `/api/summary` exposes compact dashboard metrics.
- unhandled exceptions are redacted to `{"detail": "Internal server error"}`.

Important current constraint:

- backend startup still uses deprecated FastAPI `@app.on_event("startup")` and `@app.on_event("shutdown")`.

### Mobile application

Current mobile shape:

- Framework: Flutter
- Platform target: Android-only in practice
- State management: Riverpod
- Routing: `go_router`
- API client: Dio
- Charting: `fl_chart`
- SSH/SFTP: `dartssh2`
- Secure storage: `flutter_secure_storage`
- Privileged unlock: `local_auth`

Key files:

- `mobile/lib/app.dart`
- `mobile/lib/core/routing/app_router.dart`
- `mobile/lib/core/widgets/app_scaffold.dart`
- `mobile/lib/core/config/app_settings.dart`
- `mobile/lib/core/security/app_lock_service.dart`
- `mobile/lib/core/security/secure_storage_service.dart`
- `mobile/lib/features/dashboard/`
- `mobile/lib/features/actions/`
- `mobile/lib/features/terminal/`
- `mobile/lib/features/files/`
- `mobile/lib/features/network/`
- `mobile/lib/features/settings/`

Current navigation:

- Overview
- Hardware
- Storage
- GPU
- Network
- Devices
- Actions
- Terminal
- Files
- Settings

Privileged tabs:

- Actions
- Terminal
- Files

Privileged route behavior:

- gated by `local_auth`
- unlock timeout is configurable in app settings
- lock state is managed in-memory by Riverpod

### Control agent

Current control-agent shape:

- Framework: FastAPI
- API prefix: `/api`
- Default bind: `127.0.0.1:4042`
- Methods: `GET`, `POST`, `OPTIONS`
- Purpose: fixed allowlisted privileged actions plus known-device visibility

Key files:

- `control_agent/app/main.py`
- `control_agent/app/api/router.py`
- `control_agent/app/core/config.py`
- `control_agent/app/core/auth.py`
- `control_agent/app/api/routes/health.py`
- `control_agent/app/api/routes/actions.py`
- `control_agent/app/api/routes/devices.py`
- `control_agent/app/services/wake_on_lan.py`
- `control_agent/app/services/device_probe.py`
- `control_agent/app/services/tailscale_peers.py`
- `control_agent/config/known_devices.example.yaml`

Behavior:

- all current control endpoints require bearer-token auth
- Wake-on-LAN is fixed to one server-side configured MAC address
- known devices come from YAML, not discovery
- audit-time neighbor data came only from `ip neigh`

## Endpoint Inventory

### Monitoring backend endpoints

Base prefix: `/api`

| Method | Path | Auth | Purpose |
| --- | --- | --- | --- |
| `GET` | `/health` | none | liveness/version |
| `GET` | `/system` | none | full system metrics |
| `GET` | `/gpu` | none | GPU telemetry |
| `GET` | `/docker` | none | Docker inventory summary |
| `GET` | `/summary` | none | compact dashboard metrics |
| `GET` | `/docs` | none | Swagger UI |
| `GET` | `/openapi.json` | none | OpenAPI schema |

At audit time, there were no history endpoints yet.

### Control-agent endpoints

Base prefix: `/api`

| Method | Path | Auth | Purpose |
| --- | --- | --- | --- |
| `GET` | `/health` | bearer token required | control-agent health |
| `POST` | `/actions/wake-main-pc` | bearer token required | fixed Wake-on-LAN |
| `GET` | `/devices` | bearer token required | known-device dashboard data |
At audit time there was also an approximate neighbor-view endpoint. That route
has since been removed from the default control-agent API.

At audit time there were no host endpoints and no service-control endpoints yet.

## Existing Data Models

### Monitoring backend models

Current top-level response models under `backend/app/models/`:

- `HealthResponse`
- `SummaryResponse`
- `GPUResponse`
- `DockerResponse`
- `DockerSummaryResponse`
- `SystemResponse`

`SystemResponse` already carries rich data that Phase B can reuse:

- hostname, OS, kernel, uptime, boot time
- CPU metrics and CPU specs
- memory and swap metrics
- primary disk summary
- mounted disk list
- RAID array list
- physical disk list
- network counters and top link speed

### Control-agent models

Current top-level control models under `control_agent/app/models/`:

- `HealthResponse`
- `WakeActionResponse`
- `KnownDeviceConfig`
- `KnownDeviceStatus`
- `DeviceProbeStatus`
- `DevicesResponse`
- `ObservedNeighbor`
- `NeighborsResponse`

The current device model is a known-device inventory, not a managed-host scaffold.

### Mobile models

Current tablet model groups:

- monitoring models in `mobile/lib/features/dashboard/domain/models/monitoring_models.dart`
- known-device models in `mobile/lib/features/network/domain/models/device_models.dart`
- transfer queue models in `mobile/lib/features/files/domain/models/transfer_item.dart`

Current live-chart implementation uses in-memory ring buffers only:

- `mobile/lib/core/utils/ring_buffer.dart`
- `mobile/lib/features/dashboard/presentation/providers/monitoring_controller.dart`
- `mobile/lib/features/dashboard/presentation/widgets/metric_chart.dart`

There is no persistent local history cache and no local SQLite/Drift layer.

## Existing Flutter Dependencies

Current notable dependencies from `mobile/pubspec.yaml`:

- `flutter_riverpod`
- `dio`
- `go_router`
- `fl_chart`
- `dartssh2`
- `xterm`
- `flutter_secure_storage`
- `local_auth`
- `shared_preferences`
- `path_provider`
- `file_picker`
- `open_filex`
- `permission_handler`
- `wakelock_plus`
- `intl`

Not currently present:

- `drift`
- `sqflite`
- `home_widget`
- `workmanager`

## Existing Android Native Files

Current Android-specific files inspected:

- `mobile/android/app/build.gradle.kts`
- `mobile/android/app/src/main/AndroidManifest.xml`
- `mobile/android/app/src/debug/AndroidManifest.xml`
- `mobile/android/app/src/main/kotlin/com/niko/homelab_tablet/MainActivity.kt`
- `mobile/android/key.properties.example`

Current verified Android characteristics:

- package id: `com.niko.homelab_tablet`
- Java/Kotlin target: 17
- main manifest includes `INTERNET`, `USE_BIOMETRIC`, `WAKE_LOCK`
- debug manifest enables `usesCleartextTraffic="true"`
- release signing supports `key.properties` when present
- release build falls back to debug signing when `key.properties` is absent

Not currently present:

- widget provider class
- `AppWidgetProviderInfo` XML
- `home_widget` integration
- WorkManager integration
- native deep-link handling for widgets

## Existing SSH and SFTP Implementation

### SSH

Current SSH implementation:

- `mobile/lib/features/terminal/data/ssh_connection_service.dart`
- host-key trust is stored locally through `HostFingerprintStore`
- SSH private key and optional passphrase are stored in secure storage
- trust-on-first-use prompt exists
- host fingerprint mismatch is explicitly blocked and requires trust reset
- shell sessions use `dartssh2` plus `xterm`

### SFTP

Current SFTP implementation:

- `mobile/lib/features/files/data/sftp_connection_service.dart`
- separate SFTP private key from SSH key
- separate trusted host fingerprint handling
- separate optional passphrase storage
- direct SFTP over SSH using `dartssh2`

Current virtual-root enforcement:

- enforced client-side by `mobile/lib/core/utils/path_safety.dart`
- `normalizeVirtualPath(root, path)` clamps navigation back into configured root
- `FilesPage` uses configured root from settings before loading or navigating directories

### SFTP profile storage

Current settings storage includes:

- SSH profile metadata
- SFTP profile metadata
- per-profile imported-key presence flag
- per-profile passphrase storage preference
- configured SFTP virtual root

Secrets remain in secure storage, not shared preferences.

## Existing File-Browser Capabilities

Current file-browser scope is narrower than the Expansion plan.

Current capabilities:

- connect and disconnect
- root jump and parent-directory navigation
- current-directory search filter only
- current-directory sort by name, modified time, or size
- directory listing
- file download
- queued downloads
- cancel and retry download
- open completed local download
- copy remote path
- disconnect when app backgrounds

Current enforced restrictions:

- no directory download
- no symlink navigation
- no symlink download
- no uploads
- no create directory
- no rename
- no move
- no delete or soft delete

Current transfer implementation:

- one active transfer at a time with queued follow-up items
- local application-documents download directory
- no resumable `.part` support
- no favorites
- no recent-download database
- no preview cache
- no metadata database
- no recursive search

## Existing Wake-on-LAN and Known-Device Implementation

### Wake-on-LAN

Current fixed action path:

- mobile `ActionsPage`
- mobile `DeviceDetailPage` button for WOL-enabled device
- `ControlApiClient.wakeMainPc()`
- `POST /api/actions/wake-main-pc`
- control-agent rate limiter
- server-side MAC/broadcast/port only from environment

Important current behavior:

- client cannot send arbitrary MAC addresses
- action requires bearer token
- action is rate-limited

### Known devices

Current known-device implementation:

- YAML source: `control_agent/config/known_devices.example.yaml`
- parser and concurrent probes: `control_agent/app/services/device_probe.py`
- probes supported: `tcp`, `ping`
- optional Tailscale peer overlay via `tailscale status --json`
- mobile views: `DevicesPage` and `DeviceDetailPage`

Current device inventory shape:

- static known devices only
- categories include `server`, `desktop`, `laptop`, `tablet`, `phone`, `router`, `other`
- optional `wol_enabled` plus `wake_action`
- audit-time optional neighbor section from `ip neigh`

This is not yet a generic managed-host model.

## Verified Deployment Details

This section distinguishes repository-verified facts from unverified runtime assumptions.

### Verified from repository

| Item | Status | Evidence |
| --- | --- | --- |
| Monitoring backend default bind/port | verified | `backend/app/core/config.py`, `backend/.env.example` |
| Monitoring backend systemd service name | verified from notes | `hosting-deploy-notes.txt` says `linux-monitor-backend.service` |
| Frontend nginx web root | verified from notes | `hosting-deploy-notes.txt` says `/var/www/linux-monitor/browser` |
| Bot service name | verified from notes | `hosting-deploy-notes.txt` says `linux-monitor-discord-bot.service` |
| Control agent default bind/port | verified | `control_agent/app/core/config.py`, `control_agent/.env.example` |
| Restricted SFTP intended username | documented only | `docs/RESTRICTED_SFTP_SETUP.md` says `tablet_files` |
| Restricted SFTP intended visible root | documented only | `docs/RESTRICTED_SFTP_SETUP.md` says `/warm` |
| Restricted SFTP intended backing path | documented only | `docs/RESTRICTED_SFTP_SETUP.md` says `/mnt/warm` |
| Restricted SFTP intended permission model | documented only | `docs/RESTRICTED_SFTP_SETUP.md` recommends read-only bind mount |

### Jellyfin runtime verification

Repository result:

- no `jellyfin` reference exists in backend, mobile, control agent, docs, or deployment notes
- no Docker Compose file exists in repo
- no service registry or allowlist exists yet

Therefore the following are **not verified** from the local repository:

- whether Jellyfin runs in Docker
- actual Docker container name
- actual Jellyfin health URL
- whether the future control-agent account can inspect or control the runtime

### HFS runtime verification

Repository result:

- no `HFS` or `hfs.service` reference exists in backend, mobile, control agent, docs, or deployment notes

Therefore the following are **not verified** from the local repository:

- whether HFS is managed by `hfs.service`
- actual HFS health URL
- whether the future control-agent account can inspect or control the unit

### Control-agent deployment verification

Current repository evidence:

- control-agent docs only describe manual `uvicorn` startup
- no committed systemd unit exists for control agent
- no deployment script includes control-agent installation or restart
- no repo file defines the Linux service account for control agent

Therefore the following remain **unverified**:

- deployed filesystem path for control agent
- actual service account
- whether that account already has Docker socket access
- whether that account can run `systemctl` actions

## Differences Between Plan and Local Code

1. The plan assumes a generic managed-host scaffold does not yet exist. The local repo currently has a known-device dashboard, not a managed-host layer.
2. The plan expects future service controls for Jellyfin and HFS. The local repo has no service-control registry, no adapters, and no deployment evidence for either runtime.
3. The plan assumes file-browser expansion will build on a restricted SFTP browser. That base exists, but it is download-focused only and has no metadata database.
4. The plan mentions `mobile/integration_test/`. That directory does not currently exist.
5. The plan's environment block uses `192.168.100.x` LAN addresses. The committed `known_devices.example.yaml` still uses `192.168.1.x` sample LAN addresses.
6. The monitoring backend is currently read-only as desired, but its default example bind is `0.0.0.0`, which needs manual review against the tighter private-boundary intent.
7. The control-agent docs recommend private exposure, but there is no committed deployment unit or reverse-proxy config for it yet.

## Exact Files Proposed for Phase B

Phase B should stay inside the monitoring backend and preserve the current read-only API boundary.

### Existing files to extend

- `backend/app/main.py`
  - replace startup/shutdown event wiring with a lifespan-managed history collector
- `backend/app/core/config.py`
  - add history configuration env vars
- `backend/app/api/router.py`
  - register history routes
- `backend/app/services/summary_service.py`
  - reuse compact metric gathering for overview sampling where appropriate
- `backend/app/services/system_service.py`
  - reuse full system snapshot generation for filesystem, RAID, and disk sampling
- `backend/tests/test_api_endpoints.py`
  - extend endpoint inventory expectations if history endpoints are added there

### New files proposed

- `backend/app/api/routes/history.py`
- `backend/app/models/history.py`
- `backend/app/services/history_store.py`
- `backend/app/services/history_collector.py`
- `backend/app/services/history_queries.py`
- `backend/tests/test_history_store.py`
- `backend/tests/test_history_api.py`
- `backend/tests/test_history_collector.py`
- `docs/HISTORICAL_METRICS.md`

### Why this shape fits the current repo

- route modules already live under `backend/app/api/routes/`
- typed response models already live under `backend/app/models/`
- service logic already lives under `backend/app/services/`
- tests are already split by concern under `backend/tests/`

## Proposed Phase B Boundaries

Phase B should **not** modify:

- `control_agent/`
- `mobile/`
- `frontend/`
- Samba-related configuration

Phase B should preserve:

- monitoring API remains GET-only
- live dashboard endpoints continue working if history persistence fails
- no privileged actions move into backend

## Test Status At Audit Time

Verified during this audit:

- `backend`: `python -m pytest` -> 20 passed
- `control_agent`: `python -m pytest` -> 16 passed
- `bot`: `python -m unittest discover tests -v` -> 19 passed
- `mobile`: `flutter analyze` -> passed
- `mobile`: `flutter test` -> 16 passed
- `frontend`: `npm run build` -> passed

Observed warning:

- backend tests emit FastAPI deprecation warnings because `backend/app/main.py` still uses `@app.on_event`.

## Manual Security Risks Requiring Review

1. **Monitoring backend default bind is broad.**
   - `backend/.env.example` uses `HOST=0.0.0.0`.
   - The expansion plan prefers tighter private-only boundaries.
   - Deployment should confirm localhost or tailnet-only exposure where appropriate.

2. **Control-agent deployment boundary is not yet codified.**
   - There is no committed systemd unit, reverse-proxy config, or dedicated service-account definition for control agent.
   - Before service controls are added, the actual privilege boundary must be reviewed explicitly.

3. **Jellyfin and HFS runtime assumptions are unverified.**
   - No repository evidence confirms Docker container name, unit name, or health URLs.
   - Phase E must verify real runtime details before any service-control code is written.

4. **Restricted SFTP is documented, not verified from deployment state.**
   - The repo documents a read-only bind-mounted chroot.
   - The audit cannot confirm the actual server matches that design.
   - Writes must remain disabled by default until real server permissions are reviewed.

5. **Device-side secret storage is powerful.**
   - control token, SSH key, SFTP key, and optional passphrases are stored on-device in secure storage.
   - This is appropriate for the current design, but tablet physical security and screen-lock policy matter.

6. **Release signing fallback must not be mistaken for production readiness.**
   - current Android release build falls back to debug signing when `key.properties` is missing
   - acceptable for local validation, not acceptable for distribution

7. **Known-device sample config does not match the documented homelab LAN.**
   - current example YAML uses `192.168.1.x`
   - expansion plan uses `192.168.100.x`
   - this is not a code bug, but it is a deployment-footgun if copied blindly

## Phase A Conclusion

The local repo is in a solid state for starting Phase B. The cleanest next step is to add history only in the monitoring backend, using new history-specific route, model, store, collector, and query modules while preserving the current read-only API boundary and leaving control-agent, mobile, Samba, and deployment privileges unchanged.
