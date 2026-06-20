# Managed Hosts

Managed hosts are defined in `control_agent/config/managed_hosts.example.yaml`.

Current responsibility:

- Hosts page: curated managed hosts and important machines
- Devices page: configured known devices plus Tailscale peer inventory
- Network page: traffic and history only

Current scaffold:

- configured `homelab-server`
- configured `main-pc`
- categories for host growth
- capability list for UI gating
- optional service identifiers attached to the host
- optional probe definitions for reachability checks
- optional Tailscale identity metadata
- optional URLs for monitoring/control APIs

Control-agent endpoints:

- `GET /api/hosts`
- `GET /api/hosts/{host_id}`

Only enabled hosts are returned. Configuration stays server-side for now.

## Reachability semantics

Host status is derived from configured probes and optional Tailscale peer state:

- at least one successful configured probe -> `online`
- a configured probe or known peer check fails -> `unreachable`
- no meaningful probe or peer result -> `unknown`

Do not hard-code the primary server as online. The production `homelab-server`
entry should include an explicit SSH TCP probe because the control agent may be
running on the same machine and the local node may not appear as a normal
Tailscale peer.

Required production fragment:

```yaml
probes:
  - type: tcp
    port: 22
    label: SSH
```

## Tablet actions

The tablet can show host actions according to configured capabilities:

- Overview/detail
- Hardware monitoring
- History
- Terminal
- Files
- Wake-on-LAN
- SSH/SFTP
- RDP
- Copy IP

Actions either route to existing tablet pages, launch an Android intent, copy a
configured address, or call an existing allowlisted control-agent action.
