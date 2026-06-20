# Backend-Owned Mobile Alerts

The monitoring backend owns alert evaluation, alert history, mobile registration, Firebase Cloud Messaging delivery, and retry state. The Discord bot is an independent presentation client that consumes backend alert events. The control agent owns privileged homelab actions only.

## Ownership

```text
Monitoring backend :4040/api
- telemetry and history
- sustained alert engine
- alerts.sqlite3 event/state database
- mobile-alert registration API
- Firebase Admin FCM sender
- mobile push retry outbox
- alert event feed for Discord

Control agent :4042/api
- Wake-on-LAN
- managed hosts and Tailscale-aware devices
- restricted service actions

Discord bot
- slash commands and scheduled status posts
- alert event feed consumer
- Discord-only backend-unreachable warning

Flutter tablet
- telemetry client to monitoring backend
- privileged action client to control agent
- mobile-alert client directly to monitoring backend
- Android widgets backed by monitoring snapshots
```

## Backend Environment

```text
ALERTS_ENABLED=true
ALERT_POLL_INTERVAL_SECONDS=30
ALERT_GRACE_SECONDS=300
ALERT_DB_PATH=/var/lib/linux-monitoring/alerts.sqlite3

CPU_ALERT_THRESHOLD=85
MEMORY_ALERT_THRESHOLD=90
DISK_ALERT_THRESHOLD=90
GPU_USAGE_ALERT_THRESHOLD=85
GPU_TEMP_ALERT_THRESHOLD=80

MOBILE_PUSH_ENABLED=false
MOBILE_PUSH_INCLUDE_RECOVERY=true
MOBILE_PUSH_RETRY_INITIAL_SECONDS=30
MOBILE_PUSH_RETRY_MAX_SECONDS=900
FIREBASE_SERVICE_ACCOUNT_FILE=/etc/linux-monitor-mobile-alerts/firebase-service-account.json

MOBILE_ALERT_API_TOKEN=<long-random-token>
ALERT_CONSUMER_API_TOKEN=<long-random-token>
```

Keep Firebase credentials and tokens outside the repository.

## Bot Environment

```text
MONITORING_API_BASE_URL=http://127.0.0.1:4040/api
ALERT_CONSUMER_API_TOKEN=<matching-consumer-token>
DISCORD_ALERT_CURSOR_FILE=/var/lib/linux-monitoring/discord_alert_cursor.json
DISCORD_ALERT_REPLAY_ON_FIRST_START=false
```

The bot no longer needs Firebase Admin credentials, mobile token registry files, mobile retry files, or CPU/RAM/GPU/disk alert thresholds.

## State Files

```text
/var/lib/linux-monitoring/history.sqlite3
- backend history

/var/lib/linux-monitoring/alerts.sqlite3
- backend alert state
- mobile installations
- immutable alert events
- mobile push outbox

/var/lib/linux-monitoring/discord_alert_cursor.json
- bot event cursor only

/etc/linux-monitor-mobile-alerts/firebase-service-account.json
- backend-readable Firebase Admin credential
```

Recommended permissions:

```bash
sudo install -d -m 0750 -o linux-monitor-backend -g linux-monitoring /var/lib/linux-monitoring
sudo install -d -m 0750 -o root -g linux-monitoring /etc/linux-monitor-mobile-alerts
sudo chown linux-monitor-backend:linux-monitoring /var/lib/linux-monitoring
sudo chmod 0750 /var/lib/linux-monitoring
sudo chown root:linux-monitoring /etc/linux-monitor-mobile-alerts/firebase-service-account.json
sudo chmod 0640 /etc/linux-monitor-mobile-alerts/firebase-service-account.json
```

The backend creates `alerts.sqlite3`; keep it owned by the backend service user with restrictive permissions.

## Mobile Registration API

The Android app calls the monitoring backend directly:

```text
GET    /api/mobile-alerts/status?installation_id=...
POST   /api/mobile-alerts/register
DELETE /api/mobile-alerts/register/{installation_id}
POST   /api/mobile-alerts/test
```

These routes use `MOBILE_ALERT_API_TOKEN`. They never return FCM tokens.

## Alert Consumer API

The Discord bot calls:

```text
GET /api/alerts/events?after_id=<integer>&limit=<integer>
GET /api/alerts/active
GET /api/alerts/status
```

These routes use `ALERT_CONSUMER_API_TOKEN`. They never expose mobile tokens or Firebase secrets.

## Mobile Push Semantics

Mobile FCM notifications are intentionally limited to:

```text
cpu-usage
memory-usage
gpu-usage
disk-usage:*
```

Recovery notifications use the same category set and respect both global `MOBILE_PUSH_INCLUDE_RECOVERY` and each device's `include_recovery` setting. Docker, RAID, endpoint, service-control, and generic health alerts remain Discord-only unless intentionally expanded later.

If an active mobile delivery is still pending and the condition recovers before delivery, the backend cancels the stale active delivery before queueing recovery. This avoids sending an immediate active/recovered pair after an incident has already resolved.

## Obsolete Files

After successful verification, these old files can be archived manually:

```text
/var/lib/linux-monitoring/mobile_push_tokens.json
/var/lib/linux-monitoring/mobile_push_tokens.lock
/var/lib/linux-monitoring/mobile_push_delivery_state.json
```

Do not delete live files until the backend registration, test push, and Discord event consumption have been verified.

## Read-Only Debian Verification

This block does not restart services, modify files, print tokens, or print Firebase JSON:

```bash
systemctl is-active linux-monitor-backend.service
systemctl is-active linux-monitor-discord-bot.service
systemctl is-active linux-monitor-control-agent.service

ss -ltnp | grep -E ':(4040|4042)\b' || true

sudo stat -c '%U:%G %a %n' /var/lib/linux-monitoring || true
sudo test -f /var/lib/linux-monitoring/alerts.sqlite3 && \
  sudo stat -c '%U:%G %a %n' /var/lib/linux-monitoring/alerts.sqlite3
sudo test -f /etc/linux-monitor-mobile-alerts/firebase-service-account.json && \
  sudo stat -c '%U:%G %a %n' /etc/linux-monitor-mobile-alerts/firebase-service-account.json

BACKEND_ENV_FILE="$(
  systemctl show linux-monitor-backend.service --property=EnvironmentFiles |
    sed 's/^EnvironmentFiles=//' |
    tr ' ' '\n' |
    sed 's/^-//' |
    cut -d: -f1 |
    awk 'NF {print; exit}'
)"
BACKEND_ENV_FILE="${BACKEND_ENV_FILE:-/etc/linux-monitor-backend.env}"

BOT_ENV_FILE="$(
  systemctl show linux-monitor-discord-bot.service --property=EnvironmentFiles |
    sed 's/^EnvironmentFiles=//' |
    tr ' ' '\n' |
    sed 's/^-//' |
    cut -d: -f1 |
    awk 'NF {print; exit}'
)"
BOT_ENV_FILE="${BOT_ENV_FILE:-/etc/linux-monitor-discord-bot.env}"

CONTROL_ENV_FILE="$(
  systemctl show linux-monitor-control-agent.service --property=EnvironmentFiles |
    sed 's/^EnvironmentFiles=//' |
    tr ' ' '\n' |
    sed 's/^-//' |
    cut -d: -f1 |
    awk 'NF {print; exit}'
)"
CONTROL_ENV_FILE="${CONTROL_ENV_FILE:-/etc/linux-monitor-control-agent.env}"

sudo awk -F= '/^(ALERTS_ENABLED|ALERT_DB_PATH|MOBILE_PUSH_ENABLED|FIREBASE_SERVICE_ACCOUNT_FILE|MOBILE_ALERT_API_TOKEN|ALERT_CONSUMER_API_TOKEN)=/ {print $1"=set"}' "$BACKEND_ENV_FILE"
sudo awk -F= '/^(MONITORING_API_BASE_URL|ALERT_CONSUMER_API_TOKEN|DISCORD_ALERT_CURSOR_FILE|DISCORD_ALERT_REPLAY_ON_FIRST_START)=/ {print $1"=set"}' "$BOT_ENV_FILE"
sudo awk -F= '/^(MOBILE_PUSH|FIREBASE_SERVICE_ACCOUNT_FILE)=/ {print "obsolete_control_agent_setting="$1}' "$CONTROL_ENV_FILE" || true

ALERT_CONSUMER_API_TOKEN="$(
  sudo awk -F= '/^ALERT_CONSUMER_API_TOKEN=/ {print substr($0, index($0, "=") + 1); exit}' "$BACKEND_ENV_FILE"
)"
MOBILE_ALERT_API_TOKEN="$(
  sudo awk -F= '/^MOBILE_ALERT_API_TOKEN=/ {print substr($0, index($0, "=") + 1); exit}' "$BACKEND_ENV_FILE"
)"
CONTROL_API_TOKEN="$(
  sudo awk -F= '/^CONTROL_API_TOKEN=/ {print substr($0, index($0, "=") + 1); exit}' "$CONTROL_ENV_FILE"
)"

curl -fsS -H "Authorization: Bearer ${ALERT_CONSUMER_API_TOKEN}" \
  http://127.0.0.1:4040/api/alerts/status | python3 -m json.tool
curl -fsS -H "Authorization: Bearer ${MOBILE_ALERT_API_TOKEN}" \
  'http://127.0.0.1:4040/api/mobile-alerts/status' | python3 -m json.tool
curl -fsS -H "Authorization: Bearer ${CONTROL_API_TOKEN}" \
  http://127.0.0.1:4042/api/health | python3 -m json.tool

sudo sqlite3 /var/lib/linux-monitoring/alerts.sqlite3 \
  "select 'enabled_installations=' || count(*) from mobile_installations where enabled = 1;"
sudo sqlite3 /var/lib/linux-monitoring/alerts.sqlite3 \
  "select 'pending_mobile_deliveries=' || count(*) from mobile_push_outbox where delivered_at is null and cancelled_at is null;"
sudo sqlite3 /var/lib/linux-monitoring/alerts.sqlite3 \
  "select 'latest_event_id=' || coalesce(max(event_id), 0) from alert_events;"

sudo test -f /var/lib/linux-monitoring/discord_alert_cursor.json && \
  sudo python3 - <<'PY'
import json
from pathlib import Path
payload = json.loads(Path('/var/lib/linux-monitoring/discord_alert_cursor.json').read_text())
print('discord_cursor=' + str(payload.get('last_event_id', 0)))
PY

journalctl -u linux-monitor-backend.service -n 80 --no-pager | grep -Ei 'alert|firebase|warning|error' || true
journalctl -u linux-monitor-discord-bot.service -n 80 --no-pager | grep -Ei 'alert|warning|error' || true

unset ALERT_CONSUMER_API_TOKEN MOBILE_ALERT_API_TOKEN CONTROL_API_TOKEN
```

## Manual Deployment Plan

1. Back up the live repo, systemd unit files, and environment files.
2. Pull the updated source on Debian.
3. Install backend Python dependencies from `backend/requirements.txt`.
4. Create `/var/lib/linux-monitoring` with backend-service ownership and restrictive permissions.
5. Install Firebase Admin JSON for the backend service user.
6. Add backend alert environment variables.
7. Add `MOBILE_ALERT_API_TOKEN`.
8. Add `ALERT_CONSUMER_API_TOKEN`.
9. Remove obsolete mobile-push env vars from bot and control agent.
10. Add bot event-consumer env vars.
11. Restart the backend.
12. Verify backend telemetry still works.
13. Verify `/api/alerts/status` with the consumer token.
14. Restart the control agent.
15. Verify privileged features still work.
16. Restart the bot.
17. Verify bot cursor and Discord event consumption.
18. Build the APK locally.
19. Install the APK over the existing tablet app.
20. Enter the new scoped mobile-alert backend token in tablet Settings.
21. Register the tablet.
22. Send a backend round-trip test.
23. Enable `MOBILE_PUSH_ENABLED=true` only after test succeeds.
24. Run the real-device matrix below.
25. Archive old JSON registry files after successful verification.

## Rollback Plan

1. Set backend `MOBILE_PUSH_ENABLED=false`.
2. Restart the backend if it was changed.
3. Reinstall the previous APK if tablet registration is blocked.
4. Restore previous systemd env files from backup if the bot must temporarily return to its old deployment.
5. Do not delete `alerts.sqlite3`; preserve it for incident analysis unless intentionally rolling back database state.

## Real-Device Test Matrix

1. Tablet telemetry loads through the monitoring backend.
2. Hosts, actions, and services remain through the control agent.
3. Tablet Settings separates monitoring backend URL, control-agent URL, mobile-alert backend token, and control-agent token.
4. Devices page uses configured devices plus Tailscale peers and does not depend on LAN neighbor scans.
5. Network page remains traffic/history only.
6. Register tablet while the Discord bot is stopped.
7. Send round-trip test while the Discord bot is stopped; the mobile notification still arrives.
8. Send round-trip test while the control agent is stopped; the mobile notification still arrives.
9. Foreground notification: exactly one visible heads-up pop-up.
10. Background notification: exactly one pop-up.
11. App swiped away: exactly one pop-up.
12. Screen off: prompt notification.
13. Reboot tablet before reopening app: notification still arrives if Android permits.
14. Disable Android notification permission: readiness reports blocked.
15. Mute the urgent channel: readiness reports blocked.
16. Simulate Firebase outage: backend outbox retains pending delivery.
17. Restore Firebase: pending notification retries once.
18. Trigger sustained CPU threshold with bot stopped; mobile alert still arrives.
19. Start bot afterward; it consumes backend event feed and posts Discord without affecting mobile delivery.
20. Recovery preference disabled for tablet: active arrives and recovery does not.
21. Control-agent Wake-on-LAN still works.
22. Control-agent service-control paths still work.
23. Home-screen widgets still refresh.
24. Charts remain clipped and free of spline artifacts.

Android limitation: a force-stop from Android system settings can prevent FCM delivery until the app is reopened. Swiping away from recents is not the same as force-stop.
