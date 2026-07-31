# Dashboard Control Agent read-only bridge

The Dashboard bridge is a separate FastAPI process that exposes a deliberately
small observation-only view of the Control Agent. It shares the existing device,
host, and service discovery implementations, but it does not load the full
Control Agent router and has no action handlers.

## Security contract

The bridge exposes only these authenticated `GET` routes:

```text
/health
/devices
/hosts
/hosts/{host_id}
/services
/services/{service_id}
```

There are no wake, benchmark, service-action, shell, backup, file, SSH, Docker
mutation, or systemd mutation routes. Documentation and OpenAPI HTTP endpoints
are disabled. Known paths reject mutating methods with `405`; action and unknown
paths return `404`.

Every route requires the dedicated `DASHBOARD_CONTROL_READ_TOKEN` bearer value.
The bridge also validates the direct peer address against
`DASHBOARD_CONTROL_ALLOWED_NETWORKS`. Uvicorn proxy-header processing is disabled,
so a caller cannot use `X-Forwarded-For` to bypass that check. No CORS middleware
is installed because the caller must be the Dashboard backend, never a browser.

Device responses suppress Wake-on-LAN action metadata. Service responses expose
no allowed actions or prior action state.

## Network selection

Discover the Dashboard backend's actual network instead of assuming Docker's
default bridge:

```bash
docker inspect dashboard-backend \
  --format '{{range $name, $net := .NetworkSettings.Networks}}network={{$name}} ip={{$net.IPAddress}} gateway={{$net.Gateway}}{{println}}{{end}}'
docker network inspect <dashboard-network> \
  --format '{{range .IPAM.Config}}subnet={{.Subnet}} gateway={{.Gateway}}{{println}}{{end}}'
```

Bind `DASHBOARD_CONTROL_BRIDGE_HOST` to that network's host-side gateway and set
`DASHBOARD_CONTROL_ALLOWED_NETWORKS` to the exact Dashboard container subnet.
The documentation-only environment template uses `192.0.2.0/24`; replace it with
the discovered values. Never bind the bridge to `0.0.0.0`, the LAN address, the
WAN address, or the tailnet address.

If the host firewall defaults to denying container-to-host input, add one rule
that matches the Dashboard bridge interface, source subnet, destination gateway,
TCP port, and nothing else. For UFW:

```bash
sudo ufw allow in on <dashboard-bridge-interface> \
  from <dashboard-subnet> to <dashboard-bridge-gateway> \
  port 4043 proto tcp comment 'Linux Monitor Dashboard read bridge'
```

Do not use a port-only rule or a broader private-address range. Confirm the
compiled rule contains the input interface, source, destination, protocol, and
port constraints.

On Linux, verify `host.docker.internal` before using it. It may resolve to a
different Docker bridge than the Dashboard network. When that happens, the
Dashboard network gateway address is the narrower and recommended base URL:

```text
http://<dashboard-bridge-gateway>:4043
```

## Protected environment

Install the bridge environment at:

```text
/etc/linux-monitor/dashboard-control-read.env
```

It must be `root:root` mode `0600`. Generate a new random token specifically for
this bridge. Do not reuse the full Control Agent, alert-consumer, or mobile-alert
tokens. The tracked provisioning script validates the bridge address/subnet,
generates the token without displaying it, and refuses to replace an existing
file:

```bash
sudo deploy/scripts/provision-dashboard-control-read-env.sh --check \
  <dashboard-bridge-gateway> <dashboard-subnet>
sudo deploy/scripts/provision-dashboard-control-read-env.sh \
  <dashboard-bridge-gateway> <dashboard-subnet>
```

Replace both angle-bracket placeholders before running the command. Never print
or copy the token into Git, a command argument, a browser configuration, or an
OpenAPI example.

## systemd deployment

The tracked unit is:

```text
deploy/systemd/linux-monitor-dashboard-read-bridge.service
```

Install it as:

```text
/etc/systemd/system/linux-monitor-dashboard-read-bridge.service
```

The unit uses a systemd dynamic user and receives only supplementary read access
to the `linuxcontrol` configuration group. It has no Docker group and no sudo
grant. The Docker socket is explicitly inaccessible. The source tree, protected
discovery configuration, and existing Control Agent virtual environment are
mounted read-only in the service sandbox.

Validate and install only after application tests pass:

```bash
sudo systemd-analyze verify deploy/systemd/linux-monitor-dashboard-read-bridge.service
sudo install -o root -g root -m 0644 \
  deploy/systemd/linux-monitor-dashboard-read-bridge.service \
  /etc/systemd/system/linux-monitor-dashboard-read-bridge.service
sudo systemctl daemon-reload
sudo systemctl enable --now linux-monitor-dashboard-read-bridge.service
```

Do not restart the backend, frontend, Discord bot, or full Control Agent for this
installation.

## Partial availability

The bridge does not receive Docker-socket access. Docker-backed entries remain in
the service inventory but report `runtime_state: unavailable` when no safer
inventory source is available. Error text from Docker is not returned. Systemd
status, configured HTTP health probes, device discovery, and host discovery
continue independently.

`/health` reports `read_only: true` and separate availability markers for devices,
hosts, services, and Docker runtime. Configuration failures produce sanitized
`503` responses; unexpected failures produce a generic `500` response.

## Dashboard client guidance

- Keep the bearer token only in the Dashboard backend environment.
- Use a 1-second connection timeout and a 10-second total request timeout.
- Cache `/health`, `/devices`, and `/hosts` for 15 to 30 seconds.
- Cache `/services` for 5 to 15 seconds.
- Preserve the last successful observation for up to 60 seconds when the bridge
  reports partial availability or a transient timeout.
- Treat `runtime_state: unavailable` as unknown, not stopped.
- Never derive action controls from this bridge.

## Rollback

Rollback affects only the new bridge:

```bash
sudo systemctl disable --now linux-monitor-dashboard-read-bridge.service
sudo ufw --force delete allow in on <dashboard-bridge-interface> \
  from <dashboard-subnet> to <dashboard-bridge-gateway> \
  port 4043 proto tcp comment 'Linux Monitor Dashboard read bridge'
sudo rm /etc/systemd/system/linux-monitor-dashboard-read-bridge.service
sudo systemctl daemon-reload
sudo systemctl reset-failed linux-monitor-dashboard-read-bridge.service
```

Leave `/etc/linux-monitor/dashboard-control-read.env` in place unless an operator
explicitly decides that the dedicated credential should be destroyed. Rollback
does not touch the full Control Agent or ports 4040, 4041, and 4042.
