# Dashboard control action service

The Dashboard action service is a separate FastAPI process for a deliberately
small set of privileged operations. It does not modify or extend the read-only
bridge. The read-only bridge remains observation-only on its own listener and
credential.

## API contract

Every route requires the dedicated Dashboard action bearer credential and a
direct peer address in the configured Dashboard container subnet:

```text
GET  /health
GET  /capabilities
GET  /services
GET  /services/{service_id}
GET  /actions
GET  /actions/{action_id}

POST /services/{service_id}/actions/{action}
POST /actions/wake-main-pc
```

The only service actions are `start`, `stop`, and `restart`. The wake route has
no target parameter. There is no proxy, shell, command, Docker, systemd, file,
SSH, backup, or generic action route.

Action requests have exactly these caller-controlled fields:

```json
{
  "confirmed": true,
  "request_id": "00000000-0000-4000-8000-000000000000",
  "reason": "Optional short operator note"
}
```

The request ID is a required UUID and is globally unique in the action
database. Repeating it returns the original action record without executing the
operation again. A target with a queued or running action rejects a different
request with `409 Conflict`.

Accepted requests return `202 Accepted`, an action ID, the request ID, the
target ID, current state, acceptance timestamp, and `/actions/{action_id}`
polling location. Terminal states are `succeeded`, `failed`, `rejected`, and
`timed_out`; active states are `queued` and `running`.

## Registry boundary

The live registry is:

```text
/etc/linux-monitor/dashboard-managed-actions.yml
```

It must be `root:root` mode `0600`, must not be tracked, and is validated both
by the API at startup and independently by the root helper on every operation.
Systemd passes a private read-only credential copy to the unprivileged API with
`LoadCredential`; the helper always reads the protected original.

The public example is
`control_agent/config/dashboard-managed-actions.example.yaml`. It contains only
documentation values.

Validation rejects unknown fields and kinds, duplicate IDs, relative or
unexpected path fields, shell metacharacters, wildcard targets, unsupported
actions, invalid timeouts, unsafe systemd units, protected containers, invalid
MAC addresses, and invalid wake destinations.

The `docker_container` adapter controls only an existing, exact container. The
registry also pins its expected Compose project and service labels, which are
verified before every operation. It deliberately does not evaluate a Compose
file. This is required when Compose manifests live on storage that cannot
enforce restrictive POSIX permissions. Do not add a Compose-file adapter until
the complete manifest and environment input chain is root-controlled and not
writable by unrelated accounts.

The registry may define exact systemd service units for future use, but the
helper permanently excludes the action service, read-only bridge, Docker,
networking, firewall, SSH, Samba, Tailscale, and other recovery-critical units.
The initial registry should contain only targets reviewed on the deployment
host.

## Credential and state

The dedicated environment is:

```text
/etc/linux-monitor/dashboard-control-action.env
DASHBOARD_CONTROL_ACTION_TOKEN
```

The file must be `root:root` mode `0600`. Generate a new token; never reuse the
full Control Agent, read-only bridge, alert, or mobile-alert credential.

Action history is stored at:

```text
/var/lib/linux-monitor/dashboard-actions/dashboard-actions.db
```

The dedicated state directory is owned by the action-service account and is
the only host path writable inside its systemd sandbox. SQLite uses WAL,
indexed request IDs and timestamps, a unique request-ID constraint, atomic
state transitions, startup recovery, bounded retention, and `PRAGMA
quick_check`. Records contain sanitized summaries and error codes, not raw
stdout, stderr, environments, credentials, or command lines.

## Privilege boundary

The API runs as `linux-monitor-action`, which must not belong to the Docker
group. It executes no Docker or systemd command directly. Sudo permits only:

```text
/usr/local/libexec/linux-monitor-dashboard-action-helper
```

The sudoers rule requires zero command-line arguments. A bounded JSON document
containing only registry service ID, enumerated action, and internal action ID
is sent over stdin. The root-owned helper rejects extra fields, reloads the
root-owned registry, resolves the actual target, uses fixed absolute binaries
and subprocess argument arrays, and never uses a shell.

The tracked source and sudoers definition are:

```text
deploy/scripts/linux-monitor-dashboard-action-helper.py
deploy/sudoers/linux-monitor-dashboard-action
```

Install the helper `root:root` mode `0755` and sudoers file `root:root` mode
`0440`. Validate the latter with `visudo -cf` before installation. There is no
direct sudo grant for a shell, `systemctl`, Docker, Compose, or arbitrary
commands.

The service account remains locked and uses `/usr/sbin/nologin`. On PAM-based
systems, sudo otherwise rejects a locked account before evaluating the exact
`NOPASSWD` command rule. The dedicated sudoers file therefore disables only PAM
account validation for `linux-monitor-action`; it does not enable login,
password authentication, a shell, or any additional command. This exception is
scoped to the same account whose sole sudo command is the no-argument helper.

The service unit must permit the reviewed sudo transition, so it cannot use
`NoNewPrivileges=true`. Other hardening remains enabled, and the capability
bounding set is limited to the identity-transition capabilities needed by sudo
and `CAP_NET_RAW` for interface-bound Wake-on-LAN. The unprivileged API receives
no ambient capability.

## Wake-on-LAN

Only registry ID `main-pc` is accepted. The caller cannot provide a MAC,
broadcast destination, interface, port, or arbitrary host ID. Provisioning
copies the already-reviewed Main PC wake settings from protected Control Agent
configuration without printing them, resolves the egress interface from the
configured Main PC address, and validates the broadcast against that interface.

The helper builds a standard 102-byte magic packet using the same packet
contract as the full Control Agent, binds the socket to the validated interface,
and records only that the packet was sent. It never claims the PC is online;
the Dashboard must confirm that independently through read-only discovery.

## Network boundary

Discover the Dashboard backend's actual Docker network. Bind the action service
only to that network's host gateway, normally on port `4044`. Never bind to
`0.0.0.0`, loopback, the LAN address, or a tailnet address.

Add one firewall rule containing every constraint:

```bash
sudo ufw allow in on <dashboard-bridge-interface> \
  from <dashboard-subnet> to <dashboard-bridge-gateway> \
  port 4044 proto tcp comment 'Linux Monitor Dashboard action service'
```

Do not add Docker port publication, NAT, a port-only firewall rule, or a broad
private-address allowance. Uvicorn proxy-header processing is disabled, and no
CORS middleware is installed because the only caller is the Dashboard backend.

## Deployment sequence

Run application and security tests before creating live files. Then:

```bash
sudo deploy/scripts/provision-dashboard-control-action-env.sh --check \
  <dashboard-bridge-gateway> <dashboard-subnet>
sudo deploy/scripts/provision-dashboard-managed-actions.py --check \
  --service-id <reviewed-id> --service-name '<reviewed-name>' \
  --container-name <exact-container> \
  --compose-project <expected-project> \
  --compose-service <expected-service> \
  --health-url http://127.0.0.1:<port>/health
```

Create the dedicated system user with a locked login and no supplementary
groups. Create `/var/lib/linux-monitor/dashboard-actions` for that user with
mode `0750`. Install the helper and validated sudoers file before provisioning
the protected environment and registry. The provisioning tools refuse to
overwrite either live file.

Install the tracked unit as:

```text
/etc/systemd/system/linux-monitor-dashboard-action.service
```

Validate the installed copy with `systemd-analyze verify`, reload systemd, and
start and enable only `linux-monitor-dashboard-action.service`. Do not restart
the Monitoring API, frontend, full Control Agent, Discord bot, or read-only
bridge.

## Dashboard backend guidance

- Base URL: `http://<dashboard-bridge-gateway>:4044`
- Keep `DASHBOARD_CONTROL_ACTION_TOKEN` only in the backend environment.
- Cache `/capabilities` and `/services` for 30 to 60 seconds.
- Do not cache action submissions or individual action records.
- Use a 1-second connection timeout and a 10-second read timeout.
- Allow action submission up to 10 seconds, then poll the returned location at
  one second with backoff to five seconds.
- Treat `failed`, `rejected`, and `timed_out` as terminal; display the sanitized
  summary and error code.
- If `/health` is degraded or unavailable, disable action submission while
  leaving observation through the read-only bridge available.
- After Wake-on-LAN reports success, poll read-only host discovery rather than
  claiming the target is online.

## Rollback

Rollback affects only the action service:

```bash
sudo systemctl disable --now linux-monitor-dashboard-action.service
sudo ufw --force delete allow in on <dashboard-bridge-interface> \
  from <dashboard-subnet> to <dashboard-bridge-gateway> \
  port 4044 proto tcp comment 'Linux Monitor Dashboard action service'
sudo rm /etc/systemd/system/linux-monitor-dashboard-action.service
sudo systemctl daemon-reload
sudo systemctl reset-failed linux-monitor-dashboard-action.service
```

Leave the protected token, registry, sudoers rule, helper, and action database
in place for forensic review and a reversible redeployment unless the service
is explicitly retired. Rollback does not touch ports `4040` through `4043` or
any existing Linux Monitor unit.
