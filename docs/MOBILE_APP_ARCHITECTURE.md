# Homelab Tablet Mobile Architecture

Original Phase 0 audit and implementation plan for the Android-only Flutter
tablet app and the then-future restricted control agent.

Current update: this file started as the Phase 0 architecture plan. The repo now
contains the implemented Flutter tablet app, restricted control agent, history
API, service dashboard, managed hosts, Tailscale-aware devices, Android widgets,
backend-owned mobile alerts, SFTP background timeout, richer file previews, and
storage mount filtering. Treat unchecked phase checklist items below as
historical plan text unless a current operational doc says otherwise.

Current tablet responsibilities:

- `Overview`: clickable status chips and metric cards
- `Hardware`: CPU/memory/chassis threshold coloring where higher is worse
- `Storage`: visible filesystem view with SFTP bind mounts hidden
- `GPU`: neutral numeric values with threshold-colored utilization/VRAM bars
- `Network`: live throughput plus Day/Week/Month history, no device scans
- `Hosts`: managed hosts and important-machine actions
- `Devices`: configured known devices plus Tailscale peers
- `Services`: allowlisted service grid and service detail dashboard
- `Actions`: Main PC quick actions and Wake-on-LAN
- `Terminal`: direct SSH with secure storage and host trust
- `Files`: direct restricted SFTP with configurable background timeout
- `Settings`: in-place saves and on-device profile/token storage

Working app name: `Homelab Tablet`

Android application id: `com.niko.homelab_tablet`

## Scope

This document covers architecture only. Phase 0 does not create the Flutter app, does not create the control agent, does not edit the existing monitoring backend, does not edit the Angular frontend, does not edit the Discord bot, and does not change deployed server configuration.

The existing `backend/` remains a read-only monitoring API. Privileged actions belong only in the future `control_agent/`.

## Current Repository Audit

The repository currently contains:

```text
backend/   FastAPI read-only monitoring API
frontend/  Angular polling dashboard
bot/       Discord monitoring and alert bot
docs/      Existing documentation
```

Backend entry points:

```text
backend/run.py
backend/app/main.py
backend/app/api/router.py
backend/app/api/routes/health.py
backend/app/api/routes/system.py
backend/app/api/routes/gpu.py
backend/app/api/routes/docker.py
backend/app/api/routes/summary.py
```

Backend settings currently include:

```text
API_PREFIX=/api
HOST=0.0.0.0
PORT=4040
CORS_ORIGINS=http://localhost:4041,http://127.0.0.1:4041
CORS_ORIGIN_REGEX=
DISK_MOUNTPOINT=/
DOCKER_TIMEOUT_SECONDS=3
```

The backend has a global unhandled-exception handler that logs server-side and returns sanitized `500` responses. Docker and GPU service errors are already converted to unavailable payloads rather than crashing the API.

Frontend patterns worth reusing in Flutter:

```text
- API URL normalization from base URL, API prefix, and endpoint path.
- Nullable values render as N/A instead of null.
- Status tones map healthy/warning/critical/unknown to consistent visual states.
- Polling state keeps the last successful payload when later requests fail.
- Polling streams are shared so rebuilds do not create duplicate HTTP requests.
- Legacy fallback exists for old system payload shapes, but the mobile app should target the current backend contract first.
```

Current local Flutter and Android toolchain:

```text
Flutter: 3.41.2 stable
Dart: 3.11.0
Android SDK: 36.1.0
Android licenses: accepted
Android toolchain: healthy
```

`flutter doctor -v` reports non-Android issues for Chrome and Visual Studio. Those do not block the Android-only mobile app.

## Existing Monitoring API

Base development URL:

```text
http://localhost:4040/api
```

Preferred production URL through private Tailscale HTTPS:

```text
https://<server-magicdns-host>/monitor/api
```

Endpoints consumed by the mobile app:

```text
GET /api/health
GET /api/summary
GET /api/system
GET /api/gpu
GET /api/docker
```

The app must treat all optional hardware capability fields as nullable and must not crash if a subsystem is unavailable.

### GET /api/health

Purpose: backend reachability and version metadata.

Payload:

```text
status: "ok"
app_name: string
version: string
timestamp: ISO datetime
```

Mobile usage:

```text
- Header API status.
- Reachability health strip.
- First-launch monitoring API connection test.
```

### GET /api/summary

Purpose: compact dashboard KPIs.

Payload:

```text
hostname: string
uptime_human: string
cpu_percent: number
memory_percent: number
disk_percent: number
gpu_available: boolean
gpu_utilization_percent: number | null
gpu_temp_c: number | null
docker_available: boolean
running_containers: number
```

Mobile usage:

```text
- Primary overview cards.
- Fast polling cadence, default 5 seconds.
- CPU, memory, disk, GPU availability, and Docker convenience indicator.
```

### GET /api/system

Purpose: full host snapshot.

Top-level payload:

```text
hostname: string
os: PlatformInfo
kernel_version: string
specs: SystemSpecs
chassis_temperature_c: number | null
uptime_seconds: number
uptime_human: string
boot_time: ISO datetime
cpu: CpuMetrics
memory: MemoryMetrics
swap: SwapMetrics
disk: DiskMetrics
disks: DiskDeviceMetrics[]
raid_arrays: RaidArrayMetrics[]
physical_disks: PhysicalDiskMetrics[]
network: NetworkMetrics
```

Important nested shapes:

```text
PlatformInfo:
  system, release, version, machine, platform

CpuMetrics:
  usage_percent, physical_cores, logical_cores, load_average, temperature_c

CpuSpecs:
  model_name, vendor, architecture, physical_cores, logical_cores,
  min_frequency_mhz, max_frequency_mhz, capabilities

MemorySpecs:
  total_bytes, speed_mhz, memory_type, manufacturers, modules

MotherboardSpecs:
  vendor, model, version, chipset

GPUSpecs:
  available, reason, brand, model, driver_version, vram_total_mb,
  cuda_compute_capability, capabilities

DiskDeviceMetrics:
  device, mountpoint, fstype, total, used, free, percent, read_only,
  available, raid_array, raid_level, health

RaidArrayMetrics:
  name, device, level, state, raid_disks, active_devices,
  degraded_devices, sync_action, members, health

PhysicalDiskMetrics:
  name, device, model, vendor, serial, size_bytes, temperature_c,
  rotational, removable, state, mounted_partitions, raid_arrays, health

NetworkMetrics:
  bytes_sent, bytes_recv, packets_sent, packets_recv, top_speed_mbps
```

Mobile usage:

```text
- Hardware page.
- Storage page.
- Network page cumulative counters and throughput calculation.
- Overview health strip.
- RAID and physical disk health summaries.
```

System polling should be slower than summary polling because this endpoint performs heavier host probing. Initial target: every 15 to 30 seconds.

### GET /api/gpu

Purpose: live NVIDIA GPU telemetry, when NVML is available.

Payload:

```text
available: boolean
reason: string | null
name: string | null
temperature_c: number | null
utilization_percent: number | null
memory_total_mb: number | null
memory_used_mb: number | null
memory_free_mb: number | null
power_usage_w: number | null
fan_speed_percent: number | null
driver_version: string | null
```

Mobile usage:

```text
- GPU overview cards when available.
- GPU-focused page.
- Rolling GPU utilization, temperature, VRAM, and power charts.
- Clean unavailable state when NVML or GPU access is absent.
```

### GET /api/docker

Purpose: Docker daemon reachability and container inventory.

Payload:

```text
docker_available: boolean
reason: string | null
container_count: number
containers:
  id: string
  name: string
  image: string
  state: string
  status: string
  ports: map<string, string[]>
  created: string | null
  running_for: string | null
```

Mobile usage:

```text
- Docker availability indicator.
- Optional detail panel or Settings/debug context.
- Not a primary application purpose.
```

## Mobile App Architecture

Create the app under `mobile/` in Phase 1.

Feature-first structure:

```text
mobile/
  android/
  assets/
    icons/
  lib/
    main.dart
    app.dart
    core/
      config/
      errors/
      networking/
      routing/
      security/
      theme/
      utils/
    features/
      onboarding/
      dashboard/
      hardware/
      storage/
      gpu/
      network/
      actions/
      terminal/
      files/
      settings/
  test/
  integration_test/
  README.md
```

Core responsibilities:

```text
config:
  app constants, environment handling, build mode checks

networking:
  Dio clients, timeouts, interceptors that never log secrets

security:
  secure storage, local auth gate, trusted SSH host fingerprints

routing:
  go_router routes and privileged-tab guards

theme:
  Material 3 dark theme, status colors, spacing

utils:
  byte formatting, duration formatting, percent formatting,
  temperature formatting, ring buffers, throughput calculation
```

Feature responsibilities:

```text
dashboard:
  overview cards, health strip, stale state, chart buffers

hardware:
  identity, CPU, memory, motherboard, OS, kernel, uptime

storage:
  mounted filesystems, RAID arrays, physical disks, sorting

gpu:
  GPU telemetry page and charts

network:
  server counters, client-side throughput, known devices

actions:
  Wake Main PC and future fixed allowlisted actions

terminal:
  direct SSH profile, host-key trust, xterm terminal

files:
  direct restricted SFTP profile, file listing, downloads, transfer queue

settings:
  URLs, credentials management, polling, local auth, debug options
```

## Navigation

Wide screens use a permanent or collapsible `NavigationRail`:

```text
Overview
Hardware
Storage
GPU
Network
Devices
Actions
Terminal
Files
Settings
```

Narrow screens use bottom navigation for common tabs:

```text
Overview
Hardware
Network
Terminal
Files
```

Less common tabs move to a drawer or secondary navigation page:

```text
Storage
GPU
Devices
Actions
Settings
```

The app should optimize for tablet landscape while remaining usable in portrait and on phones. Do not lock orientation in the initial implementation.

## Polling And Stale Data

Use Riverpod providers and repositories to avoid duplicate requests from widget rebuilds.

Initial cadences:

```text
GET /api/summary  every 5 seconds by default
GET /api/gpu      every 5 to 10 seconds
GET /api/system   every 15 to 30 seconds
GET /api/health   every 15 seconds
GET /api/docker   every 30 seconds
```

Each resource state should track:

```text
data: last successful payload
isLoading: whether an initial or manual request is running
isRefreshing: whether a background refresh is running
lastSuccessfulRefresh: DateTime?
lastAttemptedRefresh: DateTime?
isStale: bool
errorMessage: string?
requestDuration: optional debug-only timing
```

Failure behavior:

```text
- Keep the last successful values visible.
- Mark values as stale.
- Show last successful refresh time.
- Stop aggressive retries after repeated failures.
- Provide manual retry.
- Use "Server unreachable" unless the app can prove Tailscale itself is disconnected.
```

Rolling chart data:

```text
- In-memory only for the first implementation.
- Default ring buffer size: 120 samples.
- At 5-second sampling this is about 10 minutes.
- Pause chart sampling when the app enters the background.
```

## Tailscale-Only Network Model

Production traffic should stay inside the tailnet.

```text
Android tablet
  |
  | Tailscale private network only
  |
  +--> HTTPS Monitoring API
  |      https://<server-magicdns-host>/monitor/api
  |      existing read-only FastAPI backend
  |
  +--> HTTPS Control API
  |      https://<server-magicdns-host>/control/api
  |      future restricted control_agent
  |
  +--> SSH TCP 22
  |      direct OpenSSH through Tailscale
  |
  +--> SFTP TCP 22
         direct restricted OpenSSH SFTP through Tailscale
```

Debug builds may support narrowly scoped cleartext URLs:

```text
http://100.64.10.22:4040/api
http://100.64.10.22:4042/api
```

Release builds must not globally enable cleartext HTTP. If Android network security config is needed, keep it debug-only.

Do not use public DNS, public port forwarding, or Tailscale Funnel for this app.

## Security Model

Read-only monitoring:

```text
- No repeated local authentication required for dashboard viewing.
- Existing monitoring backend remains GET-only and read-only.
- Mobile app never sends SSH/SFTP keys to the monitoring backend.
```

Privileged areas:

```text
Actions
Terminal
Files
```

Privileged tabs require biometric or device authentication through `local_auth`, with an unlock timeout:

```text
Immediately
1 minute
5 minutes default
15 minutes
```

Lock privileged features when:

```text
- App restarts.
- Unlock window expires.
- User manually locks.
- Android device locks.
```

Encrypted secure storage only:

```text
Control API bearer token
SSH private key
SSH key passphrase if explicitly stored
SFTP private key
SFTP key passphrase if explicitly stored
Trusted host fingerprints
```

Shared preferences are acceptable for non-sensitive settings:

```text
Polling interval
Theme preference
Keep-screen-awake preference
Base URLs
Hostnames
Ports
Usernames
Layout preferences
```

Never log:

```text
Bearer tokens
Private keys
Passphrases
Full authorization headers
Raw secure storage values
```

## SSH Terminal Design

Use `dartssh2` for direct SSH over Tailscale and `xterm` for terminal rendering. Do not proxy interactive SSH through HTTP.

Profile fields:

```text
displayName
host
port
username
privateKeyReference
passphraseStored: bool
```

Authentication:

```text
- Initial support: imported private key.
- Optional passphrase.
- Store key and passphrase only in secure storage.
- Do not support password login in the first implementation unless explicitly requested later.
```

Host-key verification:

```text
First connection:
  Show the server fingerprint and require trust or reject.

Future connection with same fingerprint:
  Connect normally.

Changed fingerprint:
  Block connection and require explicit trust reset in Settings.
```

Terminal behavior:

```text
- Request PTY shell.
- Bind SSH stream to xterm input/output.
- Resize PTY on layout/orientation changes.
- Provide reconnect and disconnect.
- Close streams and socket resources on disconnect and app lifecycle changes.
- Do not persist shell output by default.
- Do not persist command history by default.
```

Accessory key row:

```text
Esc Tab Ctrl Alt | / - _ ~ Up Down Left Right
Ctrl+C Ctrl+D Ctrl+L
```

## Restricted SFTP Design

Use `dartssh2` SFTP directly over Tailscale. Do not proxy file content through HTTP.

Use a separate restricted SFTP-only account from the unrestricted shell account. Suggested account:

```text
tablet_files
```

Server-side target design:

```text
Actual warm storage:       /mnt/warm
Restricted SFTP chroot:   /srv/tablet-sftp
Bind-mounted warm storage: /srv/tablet-sftp/warm
User-visible root:         /warm
```

Initial release is download-focused and read-only:

```text
Allowed:
  list directory
  navigate directory
  download file
  cancel download
  retry failed download
  open downloaded file

Not allowed initially:
  upload
  delete
  rename
  move
  create directory
```

Client path safety:

```text
- Normalize paths.
- Prevent navigation above configured virtual root.
- Reject malformed paths.
- Treat symlinks carefully.
- Avoid displaying server paths outside the allowed virtual root.
```

Server-side chroot or equivalent remains mandatory. The mobile UI is not a security boundary.

Transfer queue states:

```text
queued
downloading
completed
failed
cancelled
```

Downloads must stream to app-local storage or a user-selected location. Do not load large files entirely into memory.

## Proposed Control Agent Architecture

Create in a later phase:

```text
control_agent/
  app/
    main.py
    api/
      router.py
      routes/
        health.py
        devices.py
        actions.py
    core/
      config.py
      auth.py
      logging.py
      rate_limit.py
    models/
      health.py
      devices.py
      actions.py
      network.py
    services/
      wake_on_lan.py
      device_probe.py
      tailscale_peers.py
  config/
    known_devices.example.yaml
  scripts/
    wake-main-pc.sh
  tests/
  .env.example
  requirements.txt
  README.md
```

Principles:

```text
- FastAPI, matching the existing backend stack.
- Default port: 4042.
- Bearer token auth for all non-public control endpoints.
- No generic shell execution.
- No arbitrary client-supplied MAC addresses.
- No arbitrary client-supplied scan IPs.
- Dangerous values come only from server-side config.
- Sanitized errors to clients; detailed logs server-side.
```

Candidate endpoints:

```text
GET  /api/health
GET  /api/devices
GET  /api/devices/{device_id}
POST /api/actions/wake-main-pc
```

The server-side neighbor inventory idea from the original plan was removed from
the default product surface. Current device inventory should come from
configured known devices and Tailscale peers.

## Wake-on-LAN Design

The mobile app exposes a single fixed action:

```text
Wake Main PC
```

The control agent owns:

```text
MAIN_PC_MAC
MAIN_PC_BROADCAST
MAIN_PC_PORT default 9
rate limit window
known post-wake probe targets
```

The client sends no MAC address. The wake request body should be empty or contain only non-authoritative UI metadata such as a client request id.

Flow:

```text
1. User opens Actions tab.
2. Local biometric or device unlock is required.
3. User taps Wake Main PC.
4. Confirmation dialog explains the target action.
5. App sends POST /api/actions/wake-main-pc with bearer token.
6. Control agent rate-limits and sends the magic packet using configured MAC.
7. App polls known-device status for Main PC until online or timeout.
```

Tests must mock UDP packet sending and verify magic packet construction without sending real packets.

## Known Devices Dashboard

The first version is a manually configured known-device dashboard, not a router replacement.

The control agent reads server-side YAML:

```text
devices:
  - id: main-pc
    name: Main PC
    category: desktop
    lan_ip: 192.168.1.50
    tailscale_ip: 100.x.y.z
    probes:
      - type: tcp
        host: 192.168.1.50
        port: 22
      - type: tcp
        host: 192.168.1.50
        port: 3389
```

Supported probe types for the initial control agent:

```text
tcp connect with timeout
optional ping when available and permitted
optional tailscale status parsing
optional ip neigh parsing for approximate LAN observations
```

Limitations without router API access:

```text
- Cannot guarantee a complete LAN device inventory.
- Cannot reliably distinguish powered-off devices from firewalled devices.
- Cannot always detect Wi-Fi devices that do not respond to probes.
- ARP/neighbor entries are approximate and can be stale.
- Tailscale peers only cover devices in the tailnet.
```

UI wording should be honest:

```text
Known devices
Last successful check
Historical neighbor-scan wording was removed from the current tablet UI.
Server could not verify device status
```

Avoid wording like "all devices on network" unless a future router integration provides that capability.

## Package Choices

Package metadata was checked against pub.dev on 2026-06-11. Re-check during Phase 1 before writing `pubspec.yaml`.

Current observed versions:

```text
flutter_riverpod       3.3.2
dio                    5.9.2
go_router              17.3.0
fl_chart               1.2.0
dartssh2               2.17.1
xterm                  4.0.0
flutter_secure_storage 10.3.1
local_auth             3.0.1
shared_preferences     2.5.5
path_provider          2.1.5
file_picker            11.0.2
open_filex             4.7.0
permission_handler     12.0.3
wakelock_plus          1.6.1
intl                   0.20.2
json_annotation        4.12.0
json_serializable      6.14.0
build_runner           2.15.0
freezed                3.2.5
freezed_annotation     3.1.0
```

Relevant package pages:

```text
https://pub.dev/packages/flutter_riverpod
https://pub.dev/packages/dio
https://pub.dev/packages/go_router
https://pub.dev/packages/fl_chart
https://pub.dev/packages/dartssh2
https://pub.dev/packages/xterm
https://pub.dev/packages/flutter_secure_storage
https://pub.dev/packages/local_auth
https://pub.dev/packages/shared_preferences
https://pub.dev/packages/path_provider
https://pub.dev/packages/file_picker
https://pub.dev/packages/open_filex
https://pub.dev/packages/permission_handler
https://pub.dev/packages/wakelock_plus
https://pub.dev/packages/intl
https://pub.dev/packages/json_annotation
https://pub.dev/packages/json_serializable
https://pub.dev/packages/build_runner
https://pub.dev/packages/freezed
https://pub.dev/packages/freezed_annotation
```

Version notes from the audit:

```text
- Installed Flutter 3.41.2 satisfies observed Flutter constraints.
- go_router 17.3.0 requires Flutter >=3.38.0.
- wakelock_plus 1.6.1 requires Flutter >=3.38.0.
- build_runner 2.15.0 and flutter_riverpod 3.3.2 require Dart >=3.7.0.
- Dart 3.11.0 satisfies the observed Dart constraints.
```

Optional `freezed` should be adopted only if it reduces model boilerplate without slowing early progress. `json_serializable` is enough for the first monitoring models.

## Control Agent Testing Plan

Future `control_agent/` tests should cover:

```text
valid bearer token
invalid bearer token
missing bearer token
wake endpoint rejects client-supplied MAC
wake endpoint rate limiting
wake packet construction
known-device YAML parsing
malformed YAML handling
TCP probe success
TCP probe timeout
ping unavailable fallback
tailscale CLI unavailable fallback
ip neigh unavailable fallback
sanitized unexpected errors
health endpoint
```

Use mocks for subprocess, sockets, and network probes. Unit tests must not send real magic packets.

## Mobile Testing Plan

Unit tests:

```text
monitoring JSON parsing
null and partial telemetry handling
byte formatting
duration formatting
temperature formatting
ring buffer behavior
throughput calculation
negative network-counter deltas
counter reset handling
stale data state
API error mapping
SFTP path normalization
prevent navigation above virtual root
host-fingerprint storage
privileged-tab timeout
transfer progress state
```

Widget tests:

```text
overview loading state
overview success state
overview offline stale state
GPU unavailable state
RAID healthy, warning, and critical states
storage table rendering
tablet navigation rail
narrow bottom navigation
wake confirmation dialog
locked privileged-tab flow
terminal disconnected state
files disconnected state
transfer queue rendering
```

Manual integration tests should use environment variables or ignored local configuration, never committed credentials.

## Phase Checklist

### Phase 0: Audit And Planning

```text
[x] Inspect existing backend API models and routes.
[x] Inspect existing Angular dashboard formatting and polling behavior.
[x] Confirm current Flutter SDK.
[x] Confirm Android SDK setup.
[x] Create feature branch.
[x] Write docs/MOBILE_APP_ARCHITECTURE.md.
```

Deliverable: architecture document only.

### Phase 1: Flutter Scaffold

```text
[ ] Create mobile/.
[ ] Add Android-only Flutter project.
[ ] Add dependencies after re-checking package versions.
[ ] Configure Material 3 dark theme.
[ ] Configure Riverpod.
[ ] Configure go_router.
[ ] Add responsive NavigationRail and narrow navigation.
[ ] Add placeholder pages.
[ ] Add formatting utilities.
[ ] Add base tests.
[ ] Run flutter analyze.
[ ] Run flutter test.
```

Deliverable: runnable Android Flutter shell.

### Phase 2: Monitoring Dashboard

```text
[ ] Add models matching existing API payloads.
[ ] Add Dio monitoring client.
[ ] Add monitoring repository.
[ ] Add Riverpod polling providers.
[ ] Build Overview page.
[ ] Build stale-data handling.
[ ] Add local ring buffers and charts.
[ ] Build Hardware page.
[ ] Build Storage page.
[ ] Build GPU page.
[ ] Add network-throughput calculations.
```

Deliverable: Android tablet dashboard consuming existing backend only.

### Phase 3: Secure Local Configuration

```text
[ ] Add onboarding.
[ ] Add encrypted secure storage.
[ ] Add shared preferences.
[ ] Add settings page.
[ ] Add local_auth privileged-tab lock.
[ ] Add keep-screen-awake preference.
```

Deliverable: configurable secure tablet dashboard.

### Phase 4: SSH Terminal

```text
[ ] Add SSH profile.
[ ] Add key import.
[ ] Add fingerprint trust flow.
[ ] Add dartssh2 direct connection.
[ ] Add xterm TerminalView.
[ ] Add PTY handling.
[ ] Add terminal accessory key row.
[ ] Add disconnect and reconnect.
[ ] Add lifecycle cleanup.
```

Deliverable: working embedded SSH shell over Tailscale.

### Phase 5: Restricted SFTP File Explorer

```text
[ ] Add separate SFTP profile.
[ ] Add direct SFTP connection.
[ ] Add remote directory listing.
[ ] Add virtual-root path safety.
[ ] Add streaming downloads.
[ ] Add progress and cancellation.
[ ] Add downloaded-file open action.
[ ] Add transfer queue.
[ ] Write restricted SFTP server setup documentation.
```

Deliverable: warm-storage-only download browser.

### Phase 6: Control Agent And Wake-on-LAN

```text
[ ] Add control_agent/.
[ ] Add token authentication.
[ ] Add control health endpoint.
[ ] Add Wake-on-LAN action.
[ ] Add rate limiting.
[ ] Add logs.
[ ] Add unit tests.
[ ] Add Actions page in Flutter.
[ ] Add biometric gate.
```

Deliverable: safe fixed Wake Main PC action.

### Phase 7: Known Devices Dashboard

```text
[ ] Add YAML known-device configuration.
[ ] Add concurrent probes.
[ ] Add control API devices endpoint.
[ ] Add Flutter devices repository.
[ ] Add Devices page.
[ ] Add device detail page.
[ ] Add post-WOL polling for Main PC status.
```

Deliverable: known-device visibility without router dependency.

### Historical Phase 8: Optional Neighbor Scans

```text
[ ] Parse ip neigh safely.
[ ] Add optional control endpoint.
[ ] Add approximate neighbor scan panel.
[ ] Clearly label limitations.
```

Deliverable: best-effort neighbor view.

### Phase 9: Hardening And Release

```text
[ ] Run Flutter tests.
[ ] Run backend tests.
[ ] Run bot tests.
[ ] Build Angular frontend.
[ ] Run control-agent tests.
[ ] Review logs for secret leakage.
[ ] Verify host fingerprint mismatch behavior.
[ ] Verify SFTP chroot restriction.
[ ] Verify release APK contains no secrets.
[ ] Write Android release guide.
[ ] Build APK.
```

Deliverable: release APK and deployment documentation.

## Open Assumptions Requiring Manual Verification

Server and network:

```text
[ ] Exact Tailscale MagicDNS hostname for the Debian server.
[ ] Whether production uses Tailscale Serve or a private reverse proxy.
[ ] Final monitoring URL path: /monitor/api or another private proxy path.
[ ] Final control URL path: /control/api or another private proxy path.
[ ] Whether release builds should reject cleartext URLs entirely.
[ ] Whether the server has a stable Tailscale IP that should be allowed in profiles.
```

Monitoring:

```text
[ ] Live /api/system payload from the real Debian server.
[ ] Whether /mnt/warm and /mnt/storage appear in disks on the server.
[ ] Whether disk serials should be shown in the app or hidden behind a setting.
[ ] Whether GPU telemetry is available on the production server.
[ ] Whether Docker socket permissions are intentionally available to backend service user.
```

Wake-on-LAN:

```text
[ ] Main PC MAC address.
[ ] Correct broadcast address and UDP port.
[ ] BIOS/UEFI Wake-on-LAN setting enabled.
[ ] OS network adapter Wake-on-LAN setting enabled.
[ ] Whether wake works across the current subnet/VLAN layout.
```

SSH:

```text
[ ] Dedicated SSH account name for terminal access.
[ ] Allowed authentication algorithms and key type.
[ ] Expected server host-key algorithm and fingerprint format.
[ ] Whether shell account needs any login restrictions beyond existing server policy.
```

SFTP:

```text
[ ] Confirm restricted SFTP username.
[ ] Confirm chroot path and ownership.
[ ] Confirm read-only bind mount from /mnt/warm.
[ ] Confirm /mnt/storage must not be exposed.
[ ] Confirm whether symlinks inside /mnt/warm exist and how they resolve.
```

Android:

```text
[ ] Physical tablet Android version and screen size.
[ ] Whether biometric hardware is available.
[ ] Whether file picker access and open-file intents behave as expected on the target tablet.
[ ] Whether keep-screen-awake should apply only to Overview or all monitoring screens.
```

Tooling:

```text
[ ] Whether to upgrade Flutter before Phase 1 despite the current SDK being compatible.
[ ] Whether CI should run Flutter tests locally, in GitHub Actions, or manually only.
[ ] Whether Android signing keys already exist or need a new release-key procedure.
```
