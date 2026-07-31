# Service controls

Linux Monitor has two distinct service-control contracts. Do not combine them.

## Full Control Agent

The tailnet-only full Control Agent uses the protected registry:

```text
/etc/linux-monitor/control-agent/services.yaml
```

Its tracked example is `control_agent/config/services.example.yaml`. Current
fields are:

```yaml
services:
  - id: example-service
    display_name: Example Service
    host_id: homelab-server
    adapter: systemd
    target: example-service.service
    allowed_actions:
      - restart
```

The supported `adapter` values are `docker` and `systemd`; supported
`allowed_actions` values are `start`, `stop`, and `restart`. Optional display
metadata includes `category`, `description`, `url`, `ports`, `image`, and an
HTTP `health_probe`.

The full agent maps service IDs to a reviewed helper. It never accepts a unit,
container, path, or command from the client. A production helper must be
root-owned outside the repository and explicitly allowlisted. If no helper is
installed, keep the full-agent production service registry empty or omit all
actions.

Full-agent endpoints are:

```text
GET  /api/services
GET  /api/services/{service_id}
POST /api/services/{service_id}/actions/{action}
```

## Dashboard action service

The Homelab Dashboard uses a separate action service, not the full Control
Agent and never the read-only bridge. Its protected registry is:

```text
/etc/linux-monitor/dashboard-managed-actions.yml
```

It has a separate token, source-network check, port, service account, helper,
sudoers rule, SQLite history, idempotency contract, worker limit, and systemd
unit. See
[`DASHBOARD_CONTROL_ACTION_SERVICE.md`](DASHBOARD_CONTROL_ACTION_SERVICE.md) for
the complete API, deployment, and rollback contract.
