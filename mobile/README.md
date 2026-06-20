# Homelab Tablet

Android-only Flutter tablet cockpit for the private Linux monitoring stack.

The app consumes:

- Monitoring API: telemetry, history, alerts, mobile push registration, widget
  snapshots.
- Control API: Wake-on-LAN, managed hosts, known devices/Tailscale peers, and
  allowlisted service controls.
- Direct SSH/SFTP over Tailscale for terminal and file browsing.

## Current Features

- Tablet-first dark Material 3 shell with responsive navigation.
- Overview status chips and metric cards that route to the relevant pages.
- Hardware, Storage, GPU, Network, History, Hosts, Devices, Services, Actions,
  Terminal, Files, and Settings pages.
- Network live charts plus history ranges for Live, Day, Week, and Month.
- Devices page focused on configured devices plus Tailscale peers; LAN neighbor
  scan blocks are not shown.
- Hosts page for managed hosts and important machines, with SSH/SFTP/RDP/copy
  actions where configured.
- Services page with configured service cards and a service detail dashboard.
- Direct SSH terminal using `dartssh2`, secure key storage, and host-fingerprint
  trust.
- Restricted SFTP browser with configurable background timeout, capped text/code
  previews, image previews, download/open support, and external open support for
  PDF/Office files.
- Android home-screen widgets backed by non-sensitive flattened telemetry.
- Backend-owned Firebase mobile alert registration and test push flow.

## Routes

```text
/onboarding
/overview
/hardware
/storage
/gpu
/network
/history
/hosts
/hosts/:hostId
/devices
/devices/:deviceId
/actions
/terminal
/files
/services
/services/:serviceId
/settings
```

Actions, Terminal, Files, and Services are privileged routes when local unlock
is enabled.

## Run

```powershell
cd mobile
flutter pub get
flutter analyze
flutter test
flutter run
```

## Build

Debug APK:

```powershell
cd mobile
flutter build apk --debug
```

Release APK:

```powershell
cd mobile
flutter build apk --release
```

See [`../docs/ANDROID_RELEASE_GUIDE.md`](../docs/ANDROID_RELEASE_GUIDE.md) for
release signing and APK audit steps.

## Configuration

First launch opens onboarding. Configure:

```text
Monitoring API URL
Control API URL and bearer token
Mobile-alert backend token
SSH profile metadata, private key, passphrase preference, and host trust
SFTP profile metadata, private key, passphrase preference, virtual root, and host trust
SFTP background timeout
Polling intervals
Widget storage labels and background refresh interval
Tablet security and debug preferences
```

Current default development URLs are emulator-friendly. On the production
tablet, configure the Tailscale URLs:

```text
Monitoring API: http://100.64.10.22:4040/api
Control API:    http://100.64.10.22:4042/api
```

Debug builds allow cleartext HTTP through the debug Android manifest. Release
builds do not globally enable cleartext traffic.

## Storage And Threshold Behavior

- Storage hides `/srv/sftp/...` bind mounts defensively if they appear in the
  backend payload.
- Hardware and Storage values use shared threshold colors where higher values
  are worse: `0-60` healthy, `61-80` warning, `81+` critical.
- Available RAM stays neutral because higher available memory is not bad.
- GPU numeric values stay neutral; only utilization and VRAM bars use threshold
  coloring.

## Dependency Notes

The app currently pins:

```text
file_picker 11.0.2
wakelock_plus 1.5.0
```

This keeps file picking stable while retaining compatible transitive `win32`
constraints. The app also uses `url_launcher` for service links and RDP intents.
