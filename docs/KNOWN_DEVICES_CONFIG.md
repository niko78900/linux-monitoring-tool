# Known Devices Configuration

Phase 7 uses a manually curated known-devices file for device visibility without router API access.

Current tablet behavior:

- Devices shows configured known devices plus Tailscale peers from
  `tailscale status --json`.
- Observed LAN Neighbors are no longer rendered in the tablet UI.
- The Network page is traffic/history only and does not show scan or inventory
  blocks.
- The control agent still keeps the neighbor endpoint for compatibility, but it
  is not part of the primary tablet workflow.

## File location

Default path:

```text
control_agent/config/known_devices.example.yaml
```

Override with:

```text
KNOWN_DEVICES_CONFIG_PATH=/absolute/path/to/known_devices.yaml
```

## Supported categories

```text
server
desktop
laptop
tablet
phone
router
other
```

## Supported probe types

```text
tcp
ping
```

Use short probe lists. This is not meant to become a broad network scanner.
Prefer explicit Tailscale IPs and hostnames for devices that are in the tailnet.

## Example

```yaml
devices:
  - id: homelab-server
    name: Debian Server
    category: server
    lan_ip: 192.168.1.10
    tailscale_ip: 100.64.10.22
    probes:
      - type: tcp
        port: 22
        label: SSH

  - id: main-pc
    name: Main PC
    category: desktop
    lan_ip: 192.168.1.50
    wol_enabled: true
    wake_action: wake-main-pc
    probes:
      - type: tcp
        port: 3389
        label: RDP
      - type: ping
        label: ICMP
```

## Notes

- `wake_action` should stay allowlisted server-side.
- `wol_enabled` only controls whether the UI offers the fixed action.
- `tailscale_ip` is optional and is used only for matching against `tailscale status --json`.
- Devices absent from this file can still appear when they are visible as
  Tailscale peers.
- Configured devices and Tailscale peers are merged when they represent the same
  machine by configured Tailscale IP, hostname/name, or explicit identity.
- Docker bridge and stale ARP/ip-neighbor entries should not appear in the
  tablet Devices page.
