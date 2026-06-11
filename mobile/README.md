# Homelab Tablet

Android-only Flutter tablet application for the private Linux monitoring stack.

Current implementation covers Phases 1-9:

```text
Phase 1: Flutter scaffold, Material 3 dark theme, Riverpod, go_router, responsive navigation, base utilities and tests.
Phase 2: Monitoring API models, Dio client, polling controller, stale-data handling, overview, hardware, storage, GPU, and network screens.
Phase 3: Onboarding, shared preferences, secure storage wrapper, settings screen, local-auth privileged-tab gate, and overview wakelock preference.
Phase 4: Direct SSH terminal with private-key import, trusted host fingerprints, SSH connection testing, xterm terminal view, copy or paste, and touch accessory keys.
Phase 5: Restricted SFTP browser with separate key handling, directory listing clamped to the configured virtual root, streaming downloads, cancellation, local file open, and a transfer queue.
Phase 6: Separate FastAPI control agent with bearer auth, rate-limited Wake Main PC, and a privileged mobile Actions page.
Phase 7: Known devices dashboard.
Phase 8: Optional observed LAN neighbors panel backed by server-side ip neigh parsing.
Phase 9: Release hardening, Android release guide, optional release signing config, and APK audit tooling.
```

## Run

```powershell
cd mobile
flutter pub get
flutter analyze
flutter test
flutter run
```

## Configuration

First launch opens onboarding. Configure:

```text
Monitoring API URL
Control API URL and bearer token
SSH profile metadata, key import, host trust, and connection testing
SFTP profile metadata, restricted key import, host trust, and connection testing
Tablet security and polling preferences
```

Debug builds allow cleartext HTTP through the debug Android manifest. Release builds do not globally enable cleartext traffic.

## Release

Use the Android release guide:

```text
docs/ANDROID_RELEASE_GUIDE.md
```

Release signing supports `mobile/android/key.properties`. Without that file, local release builds fall back to the debug signing key and should not be distributed.

## Dependency Note

The latest `file_picker` and latest `wakelock_plus` currently conflict through incompatible `win32` constraints. This app uses:

```text
file_picker 11.0.2
wakelock_plus 1.5.0
```

This keeps the requested file picker current while retaining a compatible wakelock implementation.
