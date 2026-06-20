# Expansion Deployment Checklist

Use this to validate the expanded homelab tablet stack before wider testing.
Older phase labels remain in some historical docs, but this checklist is for
the current repository state.

## Automated verification

Run these from the repository root with the existing local environments:

```powershell
cd backend
python -m pytest

cd ..\control_agent
python -m pytest

cd ..\bot
python -m unittest discover tests -v

cd ..\frontend
npm.cmd test -- --watch=false --browsers=ChromeHeadless
npm.cmd run build

cd ..\mobile
flutter analyze
flutter test
flutter build apk --debug
flutter build apk --release

cd ..
python mobile\tool\release_audit.py mobile\build\app\outputs\flutter-apk\app-release.apk
```

## History

```text
[ ] Backend history SQLite file path is configured as intended
[ ] Retention days match operator expectations
[ ] Backend restart preserves existing history rows
[ ] 1h, 24h, 7d, and 30d history views load
[ ] Network page Live, Day, Week, and Month range buttons load the expected live/history data
[ ] History failures do not break live summary, system, GPU, or docker endpoints
```

## Hosts

```text
[ ] Only configured managed hosts appear
[ ] Homelab Server host card renders with reachable status and capabilities
[ ] Homelab Server has an explicit `probes` entry for SSH TCP port 22
[ ] Hosts without usable probes or peer data render as Unknown, not Unreachable
[ ] Existing known-device Wake-on-LAN behavior still works
[ ] Main PC RDP/SSH/copy/status actions render only from configured data
```

## Devices And Network

```text
[ ] Devices page shows configured known devices
[ ] Devices page shows Tailscale peers from the control agent
[ ] Known device and Tailscale peer duplicates are merged or clearly handled
[ ] Devices page does not render a LAN-neighbor section
[ ] Network page does not render Known Devices or scan sections
```

## Services

```text
[ ] Control agent token auth is still required
[ ] Only allowlisted services are exposed
[ ] Jellyfin start, stop, and restart work through the reviewed helper path
[ ] HFS start, stop, and restart work through the reviewed helper path
[ ] Unknown service IDs are rejected
[ ] Unknown actions are rejected
[ ] Service cards show category, target, URL/port where configured
[ ] Tapping a service opens the service detail dashboard
[ ] No arbitrary command execution path was introduced
```

## Backend-Owned Alerts

```text
[ ] ALERT_DB_PATH target directory exists and is writable only by the backend service user
[ ] MOBILE_ALERT_API_TOKEN is configured only for backend mobile-alert routes
[ ] ALERT_CONSUMER_API_TOKEN is configured for backend alert feed consumers
[ ] Firebase service-account JSON is readable by the backend service user and not by the control agent or bot
[ ] /api/mobile-alerts/status works on :4040 with the mobile-alert token
[ ] /api/alerts/status works on :4040 with the consumer token
[ ] /api/mobile-alerts/* returns 404 on the control agent :4042
[ ] Discord bot cursor file is present and advances after event delivery
[ ] Old mobile_push_tokens.json and mobile_push_delivery_state.json are archived only after successful verification
```

## Files

```text
[ ] Restricted SFTP still lands inside the configured virtual root
[ ] Cold storage is still inaccessible from the file browser
[ ] Favorites persist across app restart
[ ] Recent downloads persist across app restart
[ ] Large text previews are rejected safely
[ ] Text/code previews open for .txt and .py
[ ] PDF/Office files use external open/download flow
[ ] SFTP background timeout preserves or disconnects the session according to Settings
[ ] Upload, rename, move, and soft delete remain disabled until explicitly enabled
[ ] Soft delete moves files into `.tablet-trash`
```

## Widget

```text
[ ] Server Essentials widget can be pinned from the launcher
[ ] Widget body opens the app Overview page
[ ] Widget refresh enqueues a one-time background refresh
[ ] Periodic widget refresh is set only to 15, 30, or 60 minutes
[ ] Offline refresh keeps the last good snapshot and marks it stale
[ ] Widget storage contains no secrets
```

## Manual deployment review

```text
[ ] HISTORY_DB_PATH target directory exists and is writable by the backend service user
[ ] VISIBLE_MOUNTPOINTS or IGNORED_MOUNT_PREFIXES_EXTRA hides restricted SFTP bind mounts
[ ] control-agent service-control helper installation and sudoers review are complete
[ ] Jellyfin runtime target and HFS systemd unit were verified on the real server
[ ] `/etc/linux-monitor-control-agent/managed_hosts.yaml` contains the Homelab Server SSH probe
[ ] Backend `/var/lib/linux-monitoring/alerts.sqlite3` ownership and permissions were reviewed
[ ] Bot env has `ALERT_CONSUMER_API_TOKEN` and no mobile-push/Firebase ownership settings
[ ] Control-agent env has no `MOBILE_PUSH_*` or `FIREBASE_SERVICE_ACCOUNT_FILE`
[ ] Restricted SFTP account write permissions were reviewed before enabling write toggles
[ ] Release APK is signed with a real release keystore before distribution
```

## Output artifacts

Expected APK outputs:

```text
mobile/build/app/outputs/flutter-apk/app-debug.apk
mobile/build/app/outputs/flutter-apk/app-release.apk
```
