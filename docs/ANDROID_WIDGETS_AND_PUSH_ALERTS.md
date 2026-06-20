# Android Widgets And Push Alerts

This app uses two Android background paths:

- Home-screen widgets use `home_widget` plus WorkManager for best-effort snapshot refresh.
- Urgent resource alerts use Firebase Cloud Messaging from the monitoring backend and a high-importance Android notification channel.

WorkManager is intentionally not used for urgent alerts. Android can delay periodic work, and its minimum cadence is not suitable for prompt sustained-resource notifications.

Current boundary:

- Widgets are monitoring snapshots only and never invoke control-agent actions.
- Push alerts are sent by the monitoring backend, not by the control agent or
  Discord bot.
- Tablet Settings owns registration/test UX for mobile alerts.

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

## Backend FCM Setup

The monitoring backend owns mobile registration and FCM delivery. The control agent and Discord bot do not need Firebase credentials.

1. Create a Firebase Admin service account key.
2. Copy the JSON credential to `/etc/linux-monitor-mobile-alerts/firebase-service-account.json`.
3. Restrict it:

```bash
sudo install -d -m 0750 -o root -g linux-monitoring /etc/linux-monitor-mobile-alerts
sudo chown root:linux-monitoring /etc/linux-monitor-mobile-alerts/firebase-service-account.json
sudo chmod 0640 /etc/linux-monitor-mobile-alerts/firebase-service-account.json
```

Backend env:

```text
ALERTS_ENABLED=true
ALERT_DB_PATH=/var/lib/linux-monitoring/alerts.sqlite3
MOBILE_PUSH_ENABLED=false
MOBILE_PUSH_INCLUDE_RECOVERY=true
FIREBASE_SERVICE_ACCOUNT_FILE=/etc/linux-monitor-mobile-alerts/firebase-service-account.json
MOBILE_ALERT_API_TOKEN=<long-random-token>
ALERT_CONSUMER_API_TOKEN=<long-random-token>
```

Set `MOBILE_PUSH_ENABLED=true` only after tablet registration and the round-trip test succeed.

## Android Setup

1. Install the rebuilt APK.
2. Open Settings.
3. Confirm the Monitoring API URL points at `http://100.64.10.22:4040/api`.
4. Confirm the Control API URL points at `http://100.64.10.22:4042/api`.
5. Enter the scoped Mobile-alert backend token.
6. Grant notification permission.
7. Enable push alerts.
8. Send the round-trip test notification.
9. Open Android notification settings and confirm the `Homelab urgent alerts` channel allows pop-up, sound, and vibration.
10. Add each widget from Settings or the Android launcher.

If the tablet is used over Tailscale, keep Monitoring and Control API URLs
separate in Settings:

```text
Monitoring API: http://100.64.10.22:4040/api
Control API:    http://100.64.10.22:4042/api
```

## Alert Semantics

The monitoring backend is the alert source of truth:

- First threshold breach starts the grace timer.
- Brief spikes do not notify.
- Sustained active alerts create one event.
- Active alert state persists across backend restarts.
- Recovery creates one event.
- Backend FCM delivery uses SQLite outbox retries.

Mobile push sends only `cpu-usage`, `gpu-usage`, `memory-usage`, and `disk-usage:*`. Docker, RAID, endpoint, service-control, and generic health alerts remain Discord-only.

See [`BACKEND_OWNED_MOBILE_ALERTS.md`](BACKEND_OWNED_MOBILE_ALERTS.md) for deployment verification, rollback, and the real-device matrix.
