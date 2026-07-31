# Canonical deployment layout

The deployment should run from one Git working tree while credentials and mutable state remain outside Git. The paths below describe the homelab systemd deployment; no Linux Monitoring Tool Docker Compose project is currently active.

## Canonical source tree

```text
/mnt/warm/homelab/linux-monitoring/
├── backend/
├── bot/
├── control_agent/
├── deploy/systemd/
├── docs/
├── frontend/
└── mobile/
```

The repository contains source, tests, lockfiles, sanitized examples, and reusable deployment templates. It must not contain real `.env` files, registries, credentials, databases, logs, generated frontend dependencies, or build output.

## External local state

The preferred long-term layout is:

```text
/mnt/warm/homelab-data/linux-monitor/
├── config/
│   ├── backend.env
│   ├── bot.env
│   ├── control-agent.env
│   ├── frontend.env
│   └── control-agent/
│       ├── known_devices.yaml
│       ├── managed_hosts.yaml
│       └── services.yaml
├── credentials/
│   └── firebase-service-account.json
├── databases/
│   ├── alerts.sqlite3
│   └── history.sqlite3
├── state/
│   ├── bot/
│   │   ├── discord_alert_cursor.json
│   │   └── status_schedule_state.json
│   └── control-agent/
│       └── service_actions.json
└── logs/
```

This directory is intentionally not created or populated by repository code. Provision it during a maintenance window, preserve restrictive ownership and modes, and copy data rather than moving it until the new deployment has passed validation.

## Environment path mapping

Set these local-only environment values when adopting the external layout:

```dotenv
# backend.env
HISTORY_DB_PATH=/mnt/warm/homelab-data/linux-monitor/databases/history.sqlite3
ALERT_DB_PATH=/mnt/warm/homelab-data/linux-monitor/databases/alerts.sqlite3
FIREBASE_SERVICE_ACCOUNT_FILE=/mnt/warm/homelab-data/linux-monitor/credentials/firebase-service-account.json

# bot.env
DISCORD_ALERT_CURSOR_FILE=/mnt/warm/homelab-data/linux-monitor/state/bot/discord_alert_cursor.json
STATUS_SCHEDULE_STATE_FILE=/mnt/warm/homelab-data/linux-monitor/state/bot/status_schedule_state.json

# control-agent.env
KNOWN_DEVICES_CONFIG_PATH=/mnt/warm/homelab-data/linux-monitor/config/control-agent/known_devices.yaml
MANAGED_HOSTS_CONFIG_PATH=/mnt/warm/homelab-data/linux-monitor/config/control-agent/managed_hosts.yaml
SERVICES_CONFIG_PATH=/mnt/warm/homelab-data/linux-monitor/config/control-agent/services.yaml
SERVICE_ACTION_STATE_PATH=/mnt/warm/homelab-data/linux-monitor/state/control-agent/service_actions.json
```

Copy all other required values from the component `.env.example` files and supply secrets locally. Never copy a live environment file into Git or include its values in migration reports.

## systemd architecture

The deployment uses four services:

| Unit | Working directory | Listener or role |
| --- | --- | --- |
| `linux-monitor-backend.service` | `backend/` | HTTP API on port 4040 |
| `linux-monitor-frontend.service` | `frontend/` | built Angular SPA and `/api` proxy on port 4041 |
| `linux-monitor-control-agent.service` | `control_agent/` | control API on port 4042; bind address is host-specific |
| `linux-monitor-discord-bot.service` | `bot/` | outbound Discord client |

The tracked units in `deploy/systemd/` target the canonical source path and external state layout. Review every account, group, virtual-environment path, environment file, and bind address before installing them. Repository templates never stop, restart, enable, or reload a service automatically.

## Frontend serving models

`frontend/server.py` preserves the current systemd deployment model: it serves an existing Angular build and proxies `/api` to the backend. It does not install packages or build the frontend.

`deploy.sh` describes a separate Nginx/static-web-root workflow. It performs pulls, dependency installation, service restarts, an `rsync --delete`, and an Nginx reload, so it is not a migration or cutover command. Do not run it against the live service without a separate review and maintenance window.

## Cutover principles

1. Back up both the old live tree and the candidate Git tree.
2. Validate the candidate without production environment values or databases.
3. Stop only the four Linux Monitor services during the maintenance window.
4. Rename the old tree to a timestamped rollback path; never delete it.
5. Place the validated Git working tree at the canonical path.
6. Restore ignored local files or update units to the external layout.
7. Preserve ownership and permissions before starting anything.
8. Validate configuration, start services, and test ports 4040, 4041, and 4042.
9. If any check fails, stop the new units, restore the old directory name and units, and start the previous deployment.

Database migrations are not part of this cutover. Existing databases must be copied or referenced unchanged and tested only through read-only health/API requests.
