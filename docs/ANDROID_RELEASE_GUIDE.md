# Android Release Guide

Use this guide for Phase 9 release validation and APK generation.

## 1. Validate the repo state

Run:

```powershell
cd mobile
flutter analyze
flutter test

cd ..\backend
python -m pytest

cd ..\bot
python -m unittest discover tests -v

cd ..\frontend
npm run build

cd ..\control_agent
python -m pytest
```

## 2. Prepare release signing

The Android project supports `mobile/android/key.properties` and intentionally ignores it in git.

Create `mobile/android/key.properties` from the example:

```text
storePassword=<keystore password>
keyPassword=<key password>
keyAlias=homelab-tablet
storeFile=upload-keystore.jks
```

Place the keystore at `mobile/android/upload-keystore.jks` or update `storeFile` to the correct path.

If `key.properties` is missing, Gradle falls back to the debug signing key so local release builds still work. Do not ship a debug-signed APK.

## 3. Confirm security-sensitive behavior

Verify these items before distribution:

```text
[ ] Release manifest does not globally enable cleartext HTTP
[ ] SSH and SFTP host fingerprint resets are available in Settings
[ ] Host fingerprint mismatch tells the operator to reset trust before reconnecting
[ ] Restricted SFTP stays clamped to the configured virtual root
[ ] Server-side SFTP chroot is still enforced per docs/RESTRICTED_SFTP_SETUP.md
```

Notes:

- Cleartext HTTP is enabled only in `mobile/android/app/src/debug/AndroidManifest.xml`.
- Release builds use `mobile/android/app/src/main/AndroidManifest.xml`, which does not set `usesCleartextTraffic="true"`.
- Virtual-root path clamping is covered in the Flutter tests.

## 4. Build the APK

Run:

```powershell
cd mobile
flutter build apk --release
```

Expected output:

```text
mobile/build/app/outputs/flutter-apk/app-release.apk
```

## 5. Audit the APK

Run:

```powershell
python mobile/tool/release_audit.py mobile/build/app/outputs/flutter-apk/app-release.apk
```

The audit checks for obvious private-key markers and suspicious embedded keystore or environment files.

## 6. Final operator checklist

```text
[ ] The control API token is entered on-device, not baked into the app
[ ] SSH private key is imported on-device, not baked into the app
[ ] Restricted SFTP key is imported on-device, not baked into the app
[ ] Release APK is signed with the real release keystore
[ ] APK audit passes
```
