# Service Controls

The control agent exposes a narrow, allowlisted service registry for the
tablet Services page. Service definitions stay in server-side YAML, not in the
Flutter UI.

Configured services live in:

```text
control_agent/config/services.example.yaml
```

Override the production file with:

```text
SERVICES_CONFIG_PATH=/etc/linux-monitor-control-agent/services.yaml
```

## Registry fields

Each service entry can include:

```yaml
services:
  - id: jellyfin
    name: Jellyfin
    description: Media server
    kind: docker
    target: jellyfin
    category: media
    url: http://100.64.10.22:8096
    ports:
      - 8096/tcp
    image: jellyfin/jellyfin
    enabled: true
    actions:
      - restart
```

Supported runtime kinds:

- `docker`
- `systemd`

Supported optional metadata:

- `category`
- `description`
- `url`
- `ports`
- `image`

The mobile app uses this metadata for the service grid and detail dashboard.
If Docker or systemd status cannot be read, the service is shown as `unknown`
instead of inventing a status.

## Example homelab services

The example registry includes entries for:

- Jellyfin
- HFS
- Uptime Kuma
- Crafty
- Palworld server
- Minecraft server
- Odysseus
- ChromaDB
- SearXNG
- ntfy
- Linux Monitor Backend
- Linux Monitor Control Agent

Review each `target`, `url`, and port against the live server before copying
the example to production.

## API

Control-agent endpoints:

- `GET /api/services`
- `GET /api/services/{service_id}`
- `POST /api/services/{service_id}/actions/{action}`

Allowed actions are fixed per service and currently limited to:

- `start`
- `stop`
- `restart`

The mobile client sends only `service_id` and `action`. The control agent maps
that request through the fixed registry and rejects unsupported actions or
unknown service IDs.

The mobile detail page may also offer client-side actions such as opening or
copying a configured URL. Those do not execute commands on the server.

## Privilege boundary

Manual privilege setup is required before start/stop/restart actions can work.
The example helper is:

```text
control_agent/scripts/homelab-service-control.example.sh
```

Manual review items before deployment:

- verify every Docker container name and systemd unit name
- verify service URLs and ports
- install a root-owned helper outside the repo
- grant only the reviewed helper in sudoers if sudo is used
- keep the control agent reachable only inside the tailnet or private reverse
  proxy boundary
