# Homelab Control Agent

Restricted FastAPI control service for private homelab actions.

Current scope:

- Wake-on-LAN for the configured Main PC
- managed-host status and details
- configured known devices plus Tailscale peers
- allowlisted service status and start/stop/restart actions
- allowlisted CPU/GPU benchmark jobs with status, output tail, and stop control

The tablet uses the control agent for privileged/control data only. Monitoring
telemetry, history, widgets, mobile-alert registration, and FCM delivery stay
with the monitoring backend on `:4040/api`.

## Scope

```text
GET  /api/health
GET  /api/devices
GET  /api/hosts
GET  /api/hosts/{host_id}
GET  /api/services
GET  /api/services/{service_id}
POST /api/services/{service_id}/actions/{action}
POST /api/actions/wake-main-pc
GET  /api/benchmarks/status
POST /api/benchmarks/start
POST /api/benchmarks/stop
```

## Dashboard read-only bridge

`app.read_only_main:app` is a separate, bearer-protected server-to-server entry
point for Dashboard observations. It intentionally excludes every action router
and disables HTTP access to OpenAPI and interactive documentation. Its only
routes are `GET /health`, `/devices`, `/hosts`, `/hosts/{host_id}`, `/services`,
and `/services/{service_id}`.

Deployment, network isolation, credential handling, partial Docker behavior, and
rollback are documented in
[`docs/DASHBOARD_CONTROL_READ_BRIDGE.md`](../docs/DASHBOARD_CONTROL_READ_BRIDGE.md).

## Dashboard action service

`app.action_main:app` is a second, independent server-to-server entry point for
durable, explicitly allowlisted actions. It uses a separate token, registry,
SQLite history, service account, root-owned helper, sudoers rule, listener, and
firewall rule. It does not import the full Control Agent router and does not add
actions to the read-only bridge.

Its routes are `GET /health`, `/capabilities`, `/services`,
`/services/{service_id}`, `/actions`, and `/actions/{action_id}`, plus the two
explicit POST forms `/services/{service_id}/actions/{action}` and
`/actions/wake-main-pc`.

The complete contract and deployment procedure are in
[`docs/DASHBOARD_CONTROL_ACTION_SERVICE.md`](../docs/DASHBOARD_CONTROL_ACTION_SERVICE.md).

The service does not expose mobile-alert registration, Firebase credentials,
client-supplied MAC addresses, generic shell execution, arbitrary scripts, raw
benchmark command strings, or raw `vkmark`.

Mobile-alert registration, test push, FCM delivery, alert history, and alert event feeds are owned by the monitoring backend on `:4040/api`.

## Configuration

Copy `.env.example` to `.env` and review:

```text
CONTROL_API_TOKEN
MAIN_PC_MAC
WAKE_BROADCAST_HOST
WAKE_PORT
WAKE_RATE_LIMIT_SECONDS
KNOWN_DEVICES_CONFIG_PATH
MANAGED_HOSTS_CONFIG_PATH
SERVICES_CONFIG_PATH
SERVICE_CONTROL_HELPER_PATH
SERVICE_COMMAND_TIMEOUT_SECONDS
BENCHMARK_GPU_HELPER_PATH=/usr/local/sbin/homelab-vkmark-benchmark
BENCHMARK_MAX_DURATION_SECONDS=300
BENCHMARK_STDOUT_TAIL_LINES=80
```

Prefer binding the service to `127.0.0.1` and exposing it only through a private reverse proxy or Tailscale Serve inside the tailnet.

## Config Files

Default example files:

```text
control_agent/config/known_devices.example.yaml
control_agent/config/managed_hosts.example.yaml
control_agent/config/services.example.yaml
```

Production should point the environment variables at reviewed files under
`/etc/linux-monitor/control-agent/`.

Important deployment notes:

- The `homelab-server` managed host should include an explicit SSH TCP probe on
  port `22`; the local control-agent host may not appear as a normal Tailscale
  peer.
- Known devices are merged with `tailscale status --json` peers when identities
  match by configured IP, hostname, or alias.
- Unsupported service actions are rejected even if the tablet renders an action
  button incorrectly.
- Benchmarks are fixed server-side command allowlists only:
  - `cpu_single`: `sysbench cpu --cpu-max-prime=20000 --threads=1 --time=<duration> run`
  - `cpu_multi`: `sysbench cpu --cpu-max-prime=20000 --threads=<threads> --time=<duration> run`
  - `cpu_stress`: `stress-ng --cpu <workers> --cpu-method matrixprod --verify --metrics-brief --timeout <duration>s`
  - `gpu_vkmark`: configured GPU helper path plus `800x600`
- The GPU benchmark must use the reviewed helper wrapper, defaulting to
  `/usr/local/sbin/homelab-vkmark-benchmark`. Do not call raw `vkmark` from the
  agent. If production requires sudo/root permissions for that helper, deploy
  the control agent or sudoers rule accordingly; permission failures are
  surfaced to the client.
- Only one benchmark or stress job can run at a time.
- The old server-side neighbor inventory route is no longer exposed by default.
  Device inventory comes from configured devices and Tailscale peers.

## Run

```bash
cd control_agent
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --host 127.0.0.1 --port 4042
```

## Test

```bash
cd control_agent
pytest
```
