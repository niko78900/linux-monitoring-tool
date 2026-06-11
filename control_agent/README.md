# Homelab Control Agent

Restricted FastAPI control service for private homelab actions. Phase 6 intentionally exposes only:

```text
GET  /api/health
POST /api/actions/wake-main-pc
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
```

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
