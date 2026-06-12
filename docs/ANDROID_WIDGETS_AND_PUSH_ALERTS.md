# Android Widgets And Push Alerts

This app uses two Android background paths:

- Home-screen widgets use `home_widget` plus WorkManager for best-effort snapshot refresh.
- Urgent resource alerts use Firebase Cloud Messaging (FCM) server push and a high-importance Android notification channel.

WorkManager is intentionally not used for urgent alerts. Android can delay periodic work, and its minimum cadence is not suitable for prompt sustained-resource notifications.

## Widgets

- Server Essentials, 4 x 2: hostname, status, CPU, RAM, GPU, storage, health, optional throughput, refresh.
- Compact Status, 2 x 2: status, CPU, RAM, storage, last update, refresh.
- Performance, 4 x 2: CPU, CPU temperature, RAM, GPU, GPU temperature, status, refresh.
- Storage Health, 4 x 2: primary storage, optional secondary storage, free space, RAID/disk health, status, refresh.
- Network Activity, 4 x 2: RX/TX throughput, totals, top link speed, status, refresh.
- Quick Access, 4 x 1: deep links to Overview, Storage, Terminal, Files, and Actions.

Widget storage contains flattened non-sensitive telemetry only. It must not contain monitoring/control tokens, FCM tokens, SSH or SFTP private keys, passphrases, shell output, file contents, or arbitrary private paths.

## Firebase Console Setup

1. Create or select a Firebase project.
2. Register an Android app with application ID `com.niko.homelab_tablet`.
3. Download `google-services.json`.
4. Place it manually at `mobile/android/app/google-services.json`.
5. Keep `google-services.json` out of source control. The repository ignores this file.
6. Rebuild and install the APK after adding the file.

Do not fabricate `google-services.json`; it must come from Firebase.

## Server-Side Firebase Setup

1. Create a Firebase Admin service account key.
2. Copy the JSON credential to `/etc/linux-monitor-mobile-alerts/firebase-service-account.json`.
3. Restrict it:

```bash
sudo install -d -m 0750 -o root -g linux-monitoring /etc/linux-monitor-mobile-alerts
sudo chown root:linux-monitoring /etc/linux-monitor-mobile-alerts/firebase-service-account.json
sudo chmod 0640 /etc/linux-monitor-mobile-alerts/firebase-service-account.json
```

Never copy the service-account JSON into the APK or commit it.

## Debian Configuration

Create a shared registry path for the control agent and bot:

```bash
sudo install -d -m 0750 -o linux-monitor-control-agent -g linux-monitoring /var/lib/linux-monitoring
sudo touch /var/lib/linux-monitoring/mobile_push_tokens.json
sudo chown linux-monitor-control-agent:linux-monitoring /var/lib/linux-monitoring/mobile_push_tokens.json
sudo chmod 0640 /var/lib/linux-monitoring/mobile_push_tokens.json
```

Configure both services:

```text
MOBILE_PUSH_TOKEN_REGISTRY_FILE=/var/lib/linux-monitoring/mobile_push_tokens.json
FIREBASE_SERVICE_ACCOUNT_FILE=/etc/linux-monitor-mobile-alerts/firebase-service-account.json
```

Configure the bot:

```text
MOBILE_PUSH_ENABLED=false
MOBILE_PUSH_INCLUDE_RECOVERY=true
GPU_USAGE_ALERT_THRESHOLD=85
```

Set `MOBILE_PUSH_ENABLED=true` only after Firebase and tablet registration are verified.

## Alert Semantics

The Discord bot remains the alert engine. Mobile push is a delivery sink after the existing alert-state transition:

- First threshold breach starts the grace timer.
- Brief spikes do not notify.
- Sustained active alerts notify once.
- Active alerts persist across bot restarts.
- Recovery notices are sent when enabled.

Mobile push sends only `cpu-usage`, `gpu-usage`, `memory-usage`, and `disk-usage:*`. Docker, RAID, endpoint, service-control, and generic health alerts remain Discord-only.

## Android Setup

1. Install the rebuilt APK.
2. Open Settings.
3. Grant notification permission.
4. Enable push alerts.
5. Send the round-trip test notification.
6. Open Android notification settings and confirm the `Homelab urgent alerts` channel allows pop-up, sound, and vibration.
7. Add each widget from Settings or the Android launcher.

## Read-Only Debian Verification

This block avoids printing tokens or service-account JSON:

```bash
systemctl is-active linux-monitor-control-agent.service
systemctl is-active linux-monitor-discord-bot.service

sudo test -f /etc/linux-monitor-mobile-alerts/firebase-service-account.json && \
  sudo stat -c '%U:%G %a %n' /etc/linux-monitor-mobile-alerts/firebase-service-account.json

sudo test -f /var/lib/linux-monitoring/mobile_push_tokens.json && \
  sudo stat -c '%U:%G %a %n' /var/lib/linux-monitoring/mobile_push_tokens.json

systemctl show linux-monitor-control-agent.service --property=Environment | \
  tr ' ' '\n' | grep -E 'MOBILE_PUSH_TOKEN_REGISTRY_FILE|FIREBASE_SERVICE_ACCOUNT_FILE' | sed 's/=.*/=set/'

systemctl show linux-monitor-discord-bot.service --property=Environment | \
  tr ' ' '\n' | grep -E 'MOBILE_PUSH_ENABLED|MOBILE_PUSH_INCLUDE_RECOVERY|MOBILE_PUSH_TOKEN_REGISTRY_FILE|FIREBASE_SERVICE_ACCOUNT_FILE|GPU_USAGE_ALERT_THRESHOLD' | sed 's/=.*/=set/'

CONTROL_API_TOKEN="$(sudo cat /etc/linux-monitor-control-agent/api-token)"
curl -fsS -H "Authorization: Bearer ${CONTROL_API_TOKEN}" \
  'http://100.64.10.22:4042/api/mobile-alerts/status' | python3 -m json.tool
unset CONTROL_API_TOKEN

python3 - <<'PY'
import json
from pathlib import Path
path = Path('/var/lib/linux-monitoring/mobile_push_tokens.json')
payload = json.loads(path.read_text()) if path.exists() and path.stat().st_size else {'installations': []}
enabled = [item for item in payload.get('installations', []) if item.get('enabled')]
print(f'enabled_installations={len(enabled)}')
PY

getent hosts fcm.googleapis.com >/dev/null && echo 'firebase_dns=ok'
python3 - <<'PY'
import urllib.request
urllib.request.urlopen('https://fcm.googleapis.com', timeout=5)
print('firebase_https=ok')
PY

journalctl -u linux-monitor-control-agent.service -n 80 --no-pager | grep -Ei 'mobile-alert|error|warning' || true
journalctl -u linux-monitor-discord-bot.service -n 80 --no-pager | grep -Ei 'mobile push|firebase|error|warning' || true
```

## Manual Deployment Steps

1. Add `google-services.json` locally and rebuild the APK.
2. Copy/install the APK on the tablet.
3. Install Python dependencies for the control agent and bot.
4. Install the Firebase Admin service-account JSON on Debian with restrictive permissions.
5. Configure registry and Firebase env vars for both services.
6. Restart the control agent.
7. Register the tablet from Settings.
8. Enable `MOBILE_PUSH_ENABLED=true` for the bot.
9. Restart the Discord bot.
10. Send a round-trip test notification from Settings.

## Real-Device Test Matrix

1. App foreground: send test, expect visible heads-up notification.
2. App background: send test, expect notification without reopening app.
3. App swiped away: send test, expect notification without opening app.
4. Screen off: send test, expect lock-screen/system notification.
5. Tablet rebooted and app not opened: send test, expect FCM notification if registration remains valid.
6. Notification permission denied: Settings reports denied and test explains that visible delivery is blocked.
7. Channel muted: Settings offers Android notification settings.
8. Reinstall/token rotation: registration refreshes safely.
9. Tailscale disconnected: already-registered FCM notifications may still arrive; registration/test API calls fail until Tailscale returns.
10. Add all widgets and verify tap routing.

## Rollback

1. Set `MOBILE_PUSH_ENABLED=false` and restart the Discord bot.
2. Disable push alerts from tablet Settings or delete the installation from the registry.
3. Remove widgets from the launcher if desired.
4. Restore the previous APK if needed.
5. Remove Firebase credentials from Debian if future re-enable is not planned.
