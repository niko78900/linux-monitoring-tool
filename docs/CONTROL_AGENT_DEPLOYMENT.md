# Control Agent Deployment

The control agent is a separate FastAPI service for a narrow set of privileged actions. Keep it private.

## Scope

Current phase exposes only:

```text
GET  /api/health
POST /api/actions/wake-main-pc
```

It does not expose:

```text
shell execution
arbitrary scripts
client-supplied MAC addresses
generic device scans
```

## Recommended exposure model

Prefer:

```text
control_agent bound to 127.0.0.1
private reverse proxy or Tailscale Serve
tailnet-only HTTPS
```

Avoid public binding without explicit firewalling.

## Environment

Review and set:

```text
CONTROL_API_TOKEN
MAIN_PC_MAC
WAKE_BROADCAST_HOST
WAKE_PORT
WAKE_RATE_LIMIT_SECONDS
```

## Run manually

```bash
cd control_agent
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --host 127.0.0.1 --port 4042
```

## Validation

Confirm:

```text
[ ] /api/health rejects missing and invalid bearer tokens
[ ] /api/actions/wake-main-pc rejects missing and invalid bearer tokens
[ ] Wake requests are rate-limited
[ ] The configured MAC is used even if the client sends a different value
[ ] The service is reachable only inside the tailnet or local reverse-proxy boundary
```
