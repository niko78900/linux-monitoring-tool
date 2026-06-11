# Known Devices Configuration

Phase 7 uses a manually curated known-devices file for device visibility without router API access.

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
- Devices absent from this file are not shown in the known-devices dashboard.
