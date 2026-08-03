# Dashboard backup service

The Dashboard backup service is a dedicated, authenticated orchestration API
for creating reviewed backups on cold storage. It does not migrate application
data, change runtime paths, implement restores, delete snapshots, or accept
caller-provided filesystem paths or commands.

## API contract

The service exposes only:

```text
GET  /health
GET  /plans
GET  /plans/{plan_id}
GET  /jobs
GET  /jobs/{job_id}
POST /plans/{plan_id}/jobs
POST /jobs/{job_id}/cancel
```

Every route requires the dedicated `DASHBOARD_BACKUP_TOKEN` bearer credential
and a direct peer address in `DASHBOARD_BACKUP_ALLOWED_NETWORKS`. Proxy-header
processing, CORS, interactive documentation, and HTTP OpenAPI endpoints are
disabled. The application schema still declares the `DashboardBackupBearer`
security scheme for contract tests and generated offline clients.

A start request contains only confirmation, an idempotency key, and an optional
operator note:

```json
{
  "confirmed": true,
  "request_id": "00000000-0000-4000-8000-000000000000",
  "reason": "Operator-approved scheduled backup"
}
```

The API rejects extra fields. A new accepted job returns `202`; repeating a
request ID returns the original job with `200`. Disabled, busy, or unsafe plans
return a sanitized conflict. Capacity failures use the explicit
`insufficient_capacity` error code and HTTP `507`.

The caller can never supply a source, destination, container, database,
command, argument, environment variable, retention action, restore operation,
or deletion operation.

## Protected registry

The live registry is:

```text
/etc/linux-monitor/dashboard-backups.yml
```

It must be a regular `root:root` file with mode `0600`, below a root-owned
directory that is not writable by group or other. The tracked sanitized schema
example is `control_agent/config/dashboard-backups.example.yml`.

The registry supports only `rsync_snapshot`, `postgres_dump`, `copy_files`,
`verification`, and `manifest` steps. Startup and helper-side validation reject
unknown keys and step types, duplicate plan IDs or components, relative paths,
traversal, shell metacharacters, wildcard source paths, unapproved source roots,
symlink components, source/destination overlap, destinations outside the cold
backup root, direct live PostgreSQL storage copies, invalid timeouts, and
non-manual or malformed retention declarations.

Systemd supplies a read-only credential copy to the unprivileged API. The root
helper reads and validates the protected original on every invocation. Both
sides calculate a canonical registry fingerprint. A mismatch fails closed and
requires a service restart, preventing the API and helper from acting on
different plans.

## Destination and consistency

The only destination root is:

```text
/mnt/storage/backups
```

It and each plan directory are root-owned and mode `0700`. A job first creates
`.incomplete-<job-id>` and a `BACKUP_INCOMPLETE` marker. It writes data with
root-only permissions, verifies the output, creates `manifest.json` and
`BACKUP_COMPLETE`, changes the snapshot tree to read-only root permissions, and
uses one same-filesystem rename to publish the timestamped snapshot. Existing
incomplete or final paths are never overwritten. Incomplete directories are
never reported as valid snapshots and are retained for inspection after a
failure, timeout, or cancellation.

Rsync uses a fixed argument array, never a shell. It does not use `--delete`,
does not remove source files, and does not preserve source ownership, groups,
ACLs, or Unix modes. This is intentional for NTFS/FUSE warm storage. Content,
relative paths, and modification times are retained; destination permissions
are root-only. Unsafe external symlinks are skipped and verification rejects a
snapshot link that escapes its snapshot root.

Live Immich media is a best-effort point-in-time copy. The initial
implementation does not stop or quiesce Immich. Its manifest states that writes
can occur while rsync is reading. A stricter quiesced snapshot requires a
separate reviewed maintenance procedure and must not be added as an automatic
Dashboard action.

PostgreSQL backups use `pg_dump` in the exact running container and custom
format. No password appears in host arguments, logs, history, or manifests.
The dump must be non-empty and pass `pg_restore --list`; its SHA-256 checksum,
server version, and dump-tool version are recorded. The helper never copies the
live PostgreSQL data directory and never performs a restore.

## Capacity and storage health

Before acceptance and again before execution, the helper checks the exact cold
mount, ext4 filesystem, configured RAID device, RAID degraded state, mount
write mode, destination device, root path, required binaries, required
container identity and health, source existence, dynamic source-size estimate,
per-plan lock, free space, configured reserve, and capacity overhead. The
preflight performs a short exclusive write probe inside the dedicated backup
root and removes only that newly created probe.

Large plans can remain present but disabled. Listing a plan still returns its
assessment, estimate, free bytes, manual-retention summary, and blocking
reason. Merely listing or assessing a plan does not create a snapshot.

## Durable history

Job history is stored at:

```text
/var/lib/linux-monitor/dashboard-backups/dashboard-backups.db
```

The directory is dedicated to the locked service account. SQLite uses WAL,
full synchronization, unique request IDs, indexed request and completion
timestamps, a partial unique index preventing concurrent jobs for one plan,
atomic transitions, `PRAGMA quick_check`, startup recovery, and bounded record
retention. History pruning never deletes snapshot directories.

History contains sanitized state, progress counters, estimates, safe snapshot
and manifest paths, verification state, summary, error code, and cancellation
state. It never contains bearer tokens, database passwords, environment dumps,
secret contents, or raw subprocess output.

## Privilege and cancellation boundary

The API runs as the locked `linux-monitor-backup` account with no supplementary
groups and no Docker-group membership. Sudo permits only the no-argument path:

```text
/usr/local/libexec/linux-monitor-dashboard-backup-helper
```

The helper receives a bounded JSON object on standard input containing exactly
an internal operation, a plan ID, and a job UUID. It reloads the protected
registry and constructs every source, destination, container, database, binary,
and argument itself. The tracked sudoers rule grants no shell, Docker, rsync,
PostgreSQL, systemd, or filesystem command directly.

Each running helper records a root-only PID, process-group ID, kernel start
tick, plan, job, incomplete directory, and registry fingerprint under `/run`.
Cancellation validates all of those values against `/proc`, verifies that no
final snapshot exists, and signals only the exact helper-owned process group.
It cannot accept a PID or signal target from the API. Successful snapshots are
never removed or signalled.

## Deployment

Validate source, tests, the helper, unit, sudoers, and the live plan registry
before installation. Create `linux-monitor-backup` with a locked password,
`/usr/sbin/nologin`, and no supplementary groups. Install:

```text
deploy/scripts/linux-monitor-dashboard-backup-helper.py
  -> /usr/local/libexec/linux-monitor-dashboard-backup-helper (root:root 0755)
deploy/sudoers/linux-monitor-dashboard-backup
  -> /etc/sudoers.d/linux-monitor-dashboard-backup (root:root 0440)
deploy/systemd/linux-monitor-dashboard-backup.service
  -> /etc/systemd/system/linux-monitor-dashboard-backup.service (root:root 0644)
```

Provision the dedicated credential without displaying its value:

```bash
sudo deploy/scripts/provision-dashboard-backup-env.sh --check \
  <dashboard-bridge-gateway> <dashboard-subnet>
sudo deploy/scripts/provision-dashboard-backup-env.sh \
  <dashboard-bridge-gateway> <dashboard-subnet>
```

Bind only to the exact Dashboard bridge gateway on TCP `4045`. Add one firewall
rule containing every constraint:

```bash
sudo ufw allow in on <dashboard-bridge-interface> \
  from <dashboard-subnet> to <dashboard-bridge-gateway> \
  port 4045 proto tcp comment 'Linux Monitor Dashboard backup service'
```

Do not publish the port through Docker or add a port-only, loopback, LAN,
tailnet, WAN, default-Docker-bridge, or broad private-network rule.

## Dashboard backend handoff

Use `http://<dashboard-bridge-gateway>:4045` from the Dashboard backend only.
Keep the credential in backend server configuration, never browser state.

- Cache `/health` for 10 to 15 seconds and `/plans` for 30 to 60 seconds.
- Do not cache job starts, cancellation requests, or individual active jobs.
- Use a short connection timeout and a longer read timeout for plan assessment.
- Treat `succeeded`, `failed`, `cancelled`, `timed_out`, and `rejected` as
  terminal.
- Poll active jobs from one second with backoff to five seconds.
- Display only the API's sanitized summary and error code.
- Disable starts when health is degraded or a plan says it is blocked.
- Never infer restore or deletion controls; those routes do not exist.

## Rollback

Rollback removes only the service exposure and installed unit link:

```bash
sudo systemctl disable --now linux-monitor-dashboard-backup.service
sudo ufw --force delete allow in on <dashboard-bridge-interface> \
  from <dashboard-subnet> to <dashboard-bridge-gateway> \
  port 4045 proto tcp comment 'Linux Monitor Dashboard backup service'
sudo rm /etc/systemd/system/linux-monitor-dashboard-backup.service
sudo systemctl daemon-reload
sudo systemctl reset-failed linux-monitor-dashboard-backup.service
```

Leave the registry, credential, helper, sudoers rule, job database, incomplete
directories, and successful snapshots in place for inspection. Rollback does
not touch ports `4040` through `4044`, existing Linux Monitor units, live
application data, Docker containers, or application runtime paths.
