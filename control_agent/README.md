# Homelab Control Agent

Restricted FastAPI control service for private homelab actions.

Current scope:

- Wake-on-LAN for the configured Main PC
- managed-host status and details
- configured known devices plus Tailscale peers
- allowlisted service status and start/stop/restart actions
- optional legacy neighbor endpoint for diagnostics

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
GET  /api/neighbors
```

The service does not expose mobile-alert registration, Firebase credentials, client-supplied MAC addresses, generic shell execution, or arbitrary scripts.

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
`/etc/linux-monitor-control-agent/`.

Important deployment notes:

- The `homelab-server` managed host should include an explicit SSH TCP probe on
  port `22`; the local control-agent host may not appear as a normal Tailscale
  peer.
- Known devices are merged with `tailscale status --json` peers when identities
  match by configured IP, hostname, or alias.
- Unsupported service actions are rejected even if the tablet renders an action
  button incorrectly.
- The `GET /api/neighbors` route is retained for compatibility, but the current
  tablet Devices and Network pages no longer display LAN neighbor scans.

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
