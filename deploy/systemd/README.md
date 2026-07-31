# systemd deployment templates

These units are sanitized versions of the four services used by the homelab deployment. They assume:

- canonical source tree: `/mnt/warm/homelab/linux-monitoring`
- external local state: `/mnt/warm/homelab-data/linux-monitor`
- pre-existing Python environments under `/var/lib/homelab-venvs`
- pre-existing `linuxmon`, `linuxcontrol`, and `niko` service accounts

They do not contain credentials. Create the environment files from the component `.env.example` files and keep the real files outside Git:

```text
/mnt/warm/homelab-data/linux-monitor/config/backend.env
/mnt/warm/homelab-data/linux-monitor/config/frontend.env
/mnt/warm/homelab-data/linux-monitor/config/control-agent.env
/mnt/warm/homelab-data/linux-monitor/config/bot.env
```

The control-agent `HOST` value is machine-specific. Bind it only to an address covered by the host's existing access controls. Verify users, groups, paths, permissions, and bind addresses before installing any unit. Installing or reloading units is a separate maintenance-window action; these repository files do nothing by themselves.
