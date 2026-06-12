# Homelab Host Probe Deployment Note

The live control-agent managed-host file should include an explicit SSH TCP probe for the primary server.

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

This probe lets the control agent mark the local/self-hosted Homelab Server as online when SSH is reachable, even if the local node is not present in Tailscale peer output.
