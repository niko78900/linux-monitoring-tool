# Android Widget

The Android app includes a small widget set for home-screen status at a glance. See `docs/ANDROID_WIDGETS_AND_PUSH_ALERTS.md` for the full widget and FCM alert architecture.

Current boundary: widgets consume the same sanitized monitoring snapshot as the
tablet app. They do not call the control agent, do not expose service actions,
and do not store SSH/SFTP/control/mobile-alert secrets.

## Added packages

- `home_widget` `0.9.3`
- `workmanager` `0.9.0+3`

## Flutter files

- `mobile/lib/features/server_widget/domain/models/server_widget_snapshot.dart`
- `mobile/lib/features/server_widget/data/server_widget_routes.dart`
- `mobile/lib/features/server_widget/data/server_widget_scheduler.dart`
- `mobile/lib/features/server_widget/data/server_widget_service.dart`
- `mobile/lib/app.dart`
- `mobile/lib/main.dart`
- `mobile/lib/core/config/app_settings.dart`
- `mobile/lib/features/dashboard/presentation/providers/monitoring_controller.dart`
- `mobile/lib/features/settings/presentation/pages/settings_page.dart`

## Native Android files

- `mobile/android/app/src/main/kotlin/com/niko/homelab_tablet/ServerEssentialsWidgetProvider.kt`
- `mobile/android/app/src/main/kotlin/com/niko/homelab_tablet/CompactStatusWidgetProvider.kt`
- `mobile/android/app/src/main/kotlin/com/niko/homelab_tablet/PerformanceWidgetProvider.kt`
- `mobile/android/app/src/main/kotlin/com/niko/homelab_tablet/StorageHealthWidgetProvider.kt`
- `mobile/android/app/src/main/kotlin/com/niko/homelab_tablet/NetworkActivityWidgetProvider.kt`
- `mobile/android/app/src/main/kotlin/com/niko/homelab_tablet/QuickAccessWidgetProvider.kt`
- `mobile/android/app/src/main/res/layout/server_essentials_widget.xml`
- `mobile/android/app/src/main/res/xml/server_essentials_widget_info.xml`
- `mobile/android/app/src/main/res/drawable/widget_surface.xml`
- `mobile/android/app/src/main/res/values/colors.xml`
- `mobile/android/app/src/main/AndroidManifest.xml`

## Behavior

- The open Flutter app writes fresh widget snapshots after successful summary and system refreshes.
- Widget body tap opens the app and routes to `Overview`.
- Widget storage text opens the app `Storage` page.
- Widget refresh enqueues a one-time WorkManager refresh task through `home_widget` interactivity.
- Periodic background refresh is scheduled with WorkManager at `15`, `30`, or `60` minutes.
- `AppWidgetProviderInfo.updatePeriodMillis` is `0`; Android background work is fully WorkManager-driven.

## Stored widget snapshot

The widget stores non-sensitive flattened snapshot data only:

- hostname
- reachability and stale state
- last updated timestamp
- CPU, memory, GPU, storage, RAID and disk health summaries
- network throughput

No SSH keys, SFTP keys, tokens, shell content, or private file paths are written into widget storage.

## Settings

The tablet `Settings` page now includes:

- friendly widget storage labels
- widget background refresh interval
- show or hide the network throughput row
- Android launcher pin request

Default widget matching still uses `/mnt/storage` in app settings, but the widget snapshot stores the friendly label `Cold Storage`. If that mountpoint is not present in backend storage data, the widget falls back to the backend primary disk and a generic friendly label. Backend storage filtering also hides restricted SFTP bind mounts, so widgets should not show duplicate `/srv/sftp/...` storage entries.

## Limitations

- Android background execution timing is not real-time. Periodic work is best-effort and can run later than the requested interval.
- The widgets keep the last good snapshot on refresh failure and mark it stale or offline instead of clearing it.
- Network throughput is calculated from consecutive widget snapshots. The first successful snapshot has no throughput baseline and displays `N/A`.
