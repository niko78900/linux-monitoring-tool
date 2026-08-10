# Homelab Tablet and Mobile Homelab

One Android-only Flutter package with separately installable tablet and phone
flavors.

The app consumes:

- Monitoring API: telemetry, history, alerts, mobile push registration, widget
  snapshots.
- Control API: Wake-on-LAN, managed hosts, known devices/Tailscale peers, and
  allowlisted service controls.
- Direct SSH/SFTP over Tailscale for terminal and file browsing.

## App flavors

| Flavor | Android application ID | Scope |
| --- | --- | --- |
| `tablet` | `com.niko.homelab_tablet` | Complete tablet cockpit, including SSH, SFTP, hosts, devices, services, and actions |
| `phone` | `com.niko.homelab_monitor` | Compact read-only metrics, history, widgets, push alerts, and authenticated Wake-on-LAN |

The phone router has no SSH, SFTP/Files, Hosts, Devices, Services, benchmark,
RDP, or generic Actions routes. Its only control-agent client calls health and
the fixed `wake-main-pc` endpoint with a distinct WOL-only token.

## Current Features

- Tablet-first dark Material 3 shell with responsive navigation and subtle
  fade/slide page transitions.
- Overview status chips and metric cards that route to the relevant pages.
- Hardware, Storage, GPU, Network, History, Hosts, Devices, Services, Actions,
  Terminal, Files, and Settings pages.
- Network live charts plus history ranges for Live, Day, Week, and Month.
- Devices page focused on configured devices plus Tailscale peers; LAN neighbor
  scan blocks are not shown.
- Hosts page for managed hosts and important machines, with SSH/SFTP/RDP/copy
  actions where configured.
- Services page with configured service cards, search/filter/sort controls, and
  a service detail dashboard.
- Direct SSH terminal using `dartssh2`, secure key storage, and host-fingerprint
  trust, with a compact status header and safe quick-input chips that write only
  into the active SSH session. Stored keys are validated before parsing so
  invalid old secure-storage values do not leak raw PEM parser errors.
- Restricted SFTP browser with configurable background timeout, capped text/code
  previews, image previews, download/open support, and external open support for
  PDF/Office files or unsupported files where a system app can handle them.
  Public `.pub` keys and malformed private-key text are rejected with clear
  reimport guidance.
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

Phone routes:

```text
/onboarding
/overview
/hardware
/storage
/gpu
/network
/history
/wake
/settings
/more
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

Run the phone app:

```powershell
flutter run --flavor phone --target lib/main_phone.dart
```

`flutter test` runs the focused default suite. Heavier chart/widget/mobile-alert
regressions live in `test_extended/`; include them with:

```powershell
flutter test test test_extended
```

## Build

Tablet debug APK (the default flavor):

```powershell
cd mobile
flutter build apk --debug
```

Phone debug APK:

```powershell
flutter build apk --debug --flavor phone --target lib/main_phone.dart
```

Gradle/Kotlin currently expects a supported Java runtime such as JDK 17 or JDK
21. If Windows has Java 25 first on `PATH`, build with `JAVA_HOME` pointed at a
JDK 21 install before running `flutter build`.

Release APK:

```powershell
cd mobile
flutter build apk --release
```

For Firebase, place per-application configuration at
`android/app/src/tablet/google-services.json` and
`android/app/src/phone/google-services.json`. These credential files are
ignored by Git. Without the matching file the app still builds, but push
registration remains unavailable.

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

Phone onboarding asks only for the Monitoring API, Control Agent URL plus the
`WAKE_API_TOKEN`, and Wake authentication preferences. The token is stored
separately from the tablet's full control token in Android secure storage.

Current default development URLs are emulator-friendly. On the production
tablet, configure the Tailscale URLs:

```text
Monitoring API: http://100.64.10.22:4040/api
Control API:    http://100.64.10.22:4042/api
```

Debug builds allow cleartext HTTP through the debug Android manifest. Release
builds do not globally enable cleartext traffic.

## Structure Notes

- `FilesPage` remains the SFTP orchestration layer. Toolbar controls, current
  directory search/sort, file lists, recent downloads, and preview dialogs live
  under `features/files/presentation/widgets/`.
- `SettingsPage` owns controllers and secure-storage actions. Visible sections
  live under `features/settings/presentation/sections/`.
- `AppSettings` is grouped internally, but existing `SharedPreferences` keys are
  still read and written for update compatibility.
- Small control-agent response models use `json_serializable` with custom
  converters where null/default/list/date behavior matters.

## Storage And Threshold Behavior

- Storage hides `/srv/sftp/...` bind mounts defensively if they appear in the
  backend payload.
- Hardware and Storage values use shared threshold colors where higher values
  are worse: `0-60` healthy, `61-80` warning, `81+` critical.
- Available RAM stays neutral because higher available memory is not bad.
- Important percent and temperature values can opt into shared threshold colors
  through `MetricCard.valueTone` or `InfoRow.valueColor`.
- GPU model, driver, power, and fan values stay neutral; utilization,
  temperature, and VRAM values use threshold colors, and utilization/VRAM bars
  remain threshold-colored.

## Dependency Notes

The app currently pins:

```text
file_picker 11.0.2
wakelock_plus 1.5.0
```

This keeps file picking stable while retaining compatible transitive `win32`
constraints. The app also uses `url_launcher` for service links and RDP intents.
