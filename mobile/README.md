# Homelab Tablet

Android-only Flutter tablet application for the private Linux monitoring stack.

Current implementation covers Phases 1-3:

```text
Phase 1: Flutter scaffold, Material 3 dark theme, Riverpod, go_router, responsive navigation, base utilities and tests.
Phase 2: Monitoring API models, Dio client, polling controller, stale-data handling, overview, hardware, storage, GPU, and network screens.
Phase 3: Onboarding, shared preferences, secure storage wrapper, settings screen, local-auth privileged-tab gate, and overview wakelock preference.
```

Later phases intentionally remain placeholders:

```text
Phase 4: Direct SSH terminal.
Phase 5: Restricted SFTP file browser.
Phase 6: Control agent and Wake Main PC action.
Phase 7: Known devices dashboard.
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
Control API URL and token, optional for now
SSH profile metadata, key import comes later
SFTP profile metadata, key import comes later
Tablet security and polling preferences
```

Debug builds allow cleartext HTTP through the debug Android manifest. Release builds do not globally enable cleartext traffic.

## Dependency Note

The latest `file_picker` and latest `wakelock_plus` currently conflict through incompatible `win32` constraints. This app uses:

```text
file_picker 11.0.2
wakelock_plus 1.5.0
```

This keeps the requested file picker current while retaining a compatible wakelock implementation.
