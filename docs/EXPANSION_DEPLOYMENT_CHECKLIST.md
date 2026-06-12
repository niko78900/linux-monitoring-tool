# Expansion Deployment Checklist

Use this after Phases B through H to validate the expanded homelab tablet stack before wider testing.

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
[ ] History failures do not break live summary, system, GPU, or docker endpoints
```

## Hosts

```text
[ ] Only configured managed hosts appear
[ ] Homelab Server host card renders with reachable status and capabilities
[ ] Homelab Server has an explicit `probes` entry for SSH TCP port 22
[ ] Hosts without usable probes or peer data render as Unknown, not Unreachable
[ ] Existing known-device Wake-on-LAN behavior still works
```

## Services

```text
[ ] Control agent token auth is still required
[ ] Only allowlisted services are exposed
[ ] Jellyfin start, stop, and restart work through the reviewed helper path
[ ] HFS start, stop, and restart work through the reviewed helper path
[ ] Unknown service IDs are rejected
[ ] Unknown actions are rejected
[ ] No arbitrary command execution path was introduced
```

## Files

```text
[ ] Restricted SFTP still lands inside the configured virtual root
[ ] Cold storage is still inaccessible from the file browser
[ ] Favorites persist across app restart
[ ] Recent downloads persist across app restart
[ ] Large text previews are rejected safely
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
[ ] control-agent service-control helper installation and sudoers review are complete
[ ] Jellyfin runtime target and HFS systemd unit were verified on the real server
[ ] `/etc/linux-monitor-control-agent/managed_hosts.yaml` contains the Homelab Server SSH probe
[ ] Restricted SFTP account write permissions were reviewed before enabling write toggles
[ ] Release APK is signed with a real release keystore before distribution
```

## Output artifacts

Expected APK outputs:

```text
mobile/build/app/outputs/flutter-apk/app-debug.apk
mobile/build/app/outputs/flutter-apk/app-release.apk
```
