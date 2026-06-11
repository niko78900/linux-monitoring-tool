# Service Controls

Phase E adds allowlisted service controls through the control agent.

Configured services live in `control_agent/config/services.example.yaml`.

Initial registry:

- `jellyfin` via Docker container target `jellyfin`
- `hfs` via systemd unit target `hfs.service`

Control-agent endpoints:

- `GET /api/services`
- `GET /api/services/{service_id}`
- `POST /api/services/{service_id}/actions/{action}`

Allowed actions are fixed per service and currently limited to:

- `start`
- `stop`
- `restart`

The mobile client sends only `service_id` and `action`. The control agent maps
that request through the fixed registry.

Manual privilege setup is required. The example helper is:

- `control_agent/scripts/homelab-service-control.example.sh`

Manual review items before deployment:

- verify the actual Jellyfin container name
- verify the actual HFS systemd unit name
- verify health URLs and ports
- install a root-owned helper outside the repo
- grant only the reviewed helper in sudoers if sudo is used
