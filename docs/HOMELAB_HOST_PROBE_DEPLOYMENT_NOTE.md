# Homelab Host Probe Deployment Note

The live control-agent managed-host file should include an explicit SSH TCP probe for the primary server.

Current status behavior:

- successful configured probe -> `online`
- failed configured probe or known offline peer check -> `unreachable`
- no usable probe or peer result -> `unknown`

This avoids marking the local/self-hosted Homelab Server as unreachable just
because it does not appear as a normal Tailscale peer.

Edit this file manually on the Debian server:

```text
/etc/linux-monitor-control-agent/managed_hosts.yaml
```

Add this fragment to the `homelab-server` entry if it is missing:

```yaml
probes:
  - type: tcp
    port: 22
    label: SSH
```

This probe lets the control agent mark the local/self-hosted Homelab Server as
online when SSH is reachable, even if the local node is not present in Tailscale
peer output. Do not edit the live server automatically; review and apply the
YAML manually during deployment.
