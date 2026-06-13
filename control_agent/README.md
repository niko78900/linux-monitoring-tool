# Homelab Control Agent

Restricted FastAPI control service for private homelab actions. Current implementation exposes:

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
GET  /api/mobile-alerts/status
POST /api/mobile-alerts/register
DELETE /api/mobile-alerts/register/{installation_id}
POST /api/mobile-alerts/test
```

The service does not accept client-supplied MAC addresses and does not expose generic shell execution.

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
MOBILE_PUSH_TOKEN_REGISTRY_FILE
FIREBASE_SERVICE_ACCOUNT_FILE
```

`MOBILE_PUSH_TOKEN_REGISTRY_FILE` is shared with the Discord bot. The live
directory should be owned by group `linux-monitoring` with setgid enabled so the
control agent and bot can both use the locked registry safely.

Prefer binding the service to `127.0.0.1` and exposing it only through a private reverse proxy or Tailscale Serve inside the tailnet.

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
