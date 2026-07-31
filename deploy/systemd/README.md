# systemd deployment templates

These units are sanitized versions of the services used by the systemd deployment. They assume:

- canonical source tree: `/mnt/warm/homelab/linux-monitoring`
- protected configuration: `/etc/linux-monitor`
- mutable local state: `/var/lib/linux-monitor`
- pre-existing Python environments under `/var/lib/homelab-venvs`
- pre-existing `linuxmon`, `linuxcontrol`, and `niko` service accounts

The optional Dashboard read-only bridge uses a systemd dynamic user with
supplementary read access to the `linuxcontrol` configuration group. It neither
uses the Docker group nor receives sudo privileges.

The Dashboard action service is a separate optional component. It uses the
dedicated static `linux-monitor-action` account with no supplementary groups.
That account receives only the exact no-argument helper sudo grant documented
in [`docs/DASHBOARD_CONTROL_ACTION_SERVICE.md`](../../docs/DASHBOARD_CONTROL_ACTION_SERVICE.md).
It is never a member of the Docker group.

They do not contain credentials. Create the environment files from the component `.env.example` files and keep the real files outside Git:

```text
/etc/linux-monitor/backend.env
/etc/linux-monitor/frontend.env
/etc/linux-monitor/control-agent.env
/etc/linux-monitor/bot.env
/etc/linux-monitor/dashboard-control-read.env
/etc/linux-monitor/dashboard-control-action.env
/etc/linux-monitor/dashboard-managed-actions.yml
```

Do not place these files on the canonical source volume unless that filesystem
can enforce their requested ownership and mode.

The control-agent `HOST` value is machine-specific. Bind it only to an address covered by the host's existing access controls. Verify users, groups, paths, permissions, and bind addresses before installing any unit. Installing or reloading units is a separate maintenance-window action; these repository files do nothing by themselves.

The Dashboard bridge bind address and allowed source subnet are also
machine-specific. Discover the Dashboard Docker network and follow
[`docs/DASHBOARD_CONTROL_READ_BRIDGE.md`](../../docs/DASHBOARD_CONTROL_READ_BRIDGE.md)
before installing `linux-monitor-dashboard-read-bridge.service`.

The action service uses a separate port, token, registry, account, helper,
sudoers rule, database, and unit. Follow
[`docs/DASHBOARD_CONTROL_ACTION_SERVICE.md`](../../docs/DASHBOARD_CONTROL_ACTION_SERVICE.md)
before installing `linux-monitor-dashboard-action.service`. Never add action
routes to the read-only bridge.
