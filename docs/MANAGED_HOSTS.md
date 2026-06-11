# Managed Hosts

Managed hosts are defined in `control_agent/config/managed_hosts.example.yaml`.

Initial scaffold:

- one configured host: `homelab-server`
- categories for future device growth
- capability list for UI gating
- optional service identifiers attached to the host
- optional probe definitions for reachability checks

Control-agent endpoints:

- `GET /api/hosts`
- `GET /api/hosts/{host_id}`

Only enabled hosts are returned. Configuration stays server-side for now.
