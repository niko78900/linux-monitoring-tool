# Control Agent Deployment

The control agent is a separate FastAPI service for a narrow set of privileged actions. Keep it private.

## Scope

Current phase exposes only:

```text
GET  /api/health
GET  /api/devices
GET  /api/hosts
GET  /api/hosts/{host_id}
POST /api/actions/wake-main-pc
GET  /api/neighbors
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
MANAGED_HOSTS_CONFIG_PATH
```

## Managed host reachability

The control agent reports managed-host status from configured probes and optional Tailscale peer state. The local homelab server can be the same machine running the control agent, so do not rely exclusively on Tailscale peer discovery for that host.

Add an explicit SSH TCP probe to the live managed-host entry:

```yaml
probes:
  - type: tcp
    port: 22
    label: SSH
```

The default live path is:

```text
/etc/linux-monitor-control-agent/managed_hosts.yaml
```

With no successful probe and no usable peer state, the API reports `status: unknown` instead of treating the host as confirmed unreachable. `status: unreachable` is reserved for a failed configured probe or an offline peer check.

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
[ ] /api/hosts returns Homelab Server with status `online`, `unreachable`, or `unknown`
[ ] Homelab Server has a configured SSH TCP probe on port 22
[ ] Wake requests are rate-limited
[ ] The configured MAC is used even if the client sends a different value
[ ] The service is reachable only inside the tailnet or local reverse-proxy boundary
```

## Read-only Debian verification

Run these checks on the Debian server when validating a live deployment. They do not modify files, restart services, or print the API token.

```bash
systemctl is-active linux-monitor-control-agent.service

sudo grep -A3 -B2 'label: SSH' /etc/linux-monitor-control-agent/managed_hosts.yaml

nc -vz 127.0.0.1 22

CONTROL_API_TOKEN_FILE=/etc/linux-monitor-control-agent/api-token
CONTROL_API_TOKEN="$(sudo cat "$CONTROL_API_TOKEN_FILE")"
curl -fsS \
  -H "Authorization: Bearer ${CONTROL_API_TOKEN}" \
  http://100.64.10.22:4042/api/hosts \
  | python3 -m json.tool \
  | grep -A20 '"id": "homelab-server"'
unset CONTROL_API_TOKEN

python3 - <<'PY'
from pathlib import Path
source = Path('/opt/linux-monitoring/control_agent/app/services/managed_hosts.py')
text = source.read_text(encoding='utf-8')
checks = [
    'status == "online"',
    'return "unknown"',
    'Tailscale peer status unavailable',
]
for check in checks:
    print(f'{check}: {"present" if check in text else "missing"}')
PY
```

Expected live host fragment:

```yaml
probes:
  - type: tcp
    port: 22
    label: SSH
```

If the YAML fragment is present but `/api/hosts` still does not return `status: online` for `homelab-server`, sync the latest control-agent source to the server and restart `linux-monitor-control-agent.service` during a maintenance window.
