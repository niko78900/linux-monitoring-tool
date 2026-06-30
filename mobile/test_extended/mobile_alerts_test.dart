import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:homelab_tablet/features/mobile_alerts/data/mobile_alert_routes.dart';
import 'package:homelab_tablet/features/mobile_alerts/data/mobile_alert_service.dart';
import 'package:homelab_tablet/features/server_widget/data/server_widget_catalog.dart';

void main() {
  test('notification route mapping targets relevant screens', () {
    expect(routeForMobileAlertKey('cpu-usage'), '/overview');
    expect(routeForMobileAlertKey('memory-usage'), '/overview');
    expect(routeForMobileAlertKey('gpu-usage'), '/gpu');
    expect(routeForMobileAlertKey('disk-usage:/mnt/warm'), '/storage');
  });

  test('registration payload is built without server credentials', () {
    final payload = buildMobileAlertRegistrationPayload(
      installationId: 'install-1234',
      deviceName: 'Homelab Tablet',
      fcmToken: 'fcm-token-value',
      includeRecovery: false,
    );

    expect(payload['installation_id'], 'install-1234');
    expect(payload['platform'], 'android');
    expect(payload['enabled'], isTrue);
    expect(payload['include_recovery'], isFalse);
    expect(payload.containsKey('control_api_token'), isFalse);
    expect(payload.containsKey('firebase_service_account'), isFalse);
  });

  test('mobile alert service uses monitoring backend client', () {
    final service = File(
      'lib/features/mobile_alerts/data/mobile_alert_service.dart',
    ).readAsStringSync();
    final controlClient = File(
      'lib/features/network/data/control_api_client.dart',
    ).readAsStringSync();

    expect(service, contains('MobileAlertApiClient'));
    expect(service, contains('baseUrl: settings.monitoringApiUrl'));
    expect(service, isNot(contains('baseUrl: settings.controlApiUrl')));
    expect(controlClient, isNot(contains('/mobile-alerts')));
  });

  test('mobile alert token is separate from control token', () {
    final storage = File(
      'lib/core/security/secure_storage_service.dart',
    ).readAsStringSync();

    expect(storage, contains('control_api_token'));
    expect(storage, contains('mobile_alert_api_token'));
    expect(storage, contains('readMobileAlertToken'));
    expect(storage, contains('writeMobileAlertToken'));
  });

  test('permission labels are clear', () {
    expect(MobileNotificationPermissionState.denied.label, 'Denied');
    expect(MobileNotificationPermissionState.granted.label, 'Granted');
  });

  test('readiness messages identify notification blockers', () {
    expect(
      const MobileAlertReadiness(
        firebaseReady: false,
        tokenAvailable: false,
        permissionGranted: false,
        serverRegistered: false,
        channelExists: false,
        channelImportance: 0,
        channelSoundEnabled: false,
        channelVibrationEnabled: false,
      ).readinessMessage,
      'Firebase unavailable',
    );
    expect(
      const MobileAlertReadiness(
        firebaseReady: true,
        tokenAvailable: true,
        permissionGranted: false,
        serverRegistered: true,
        channelExists: true,
        channelImportance: 4,
        channelSoundEnabled: true,
        channelVibrationEnabled: true,
      ).readinessMessage,
      'Registered, but Android permission is denied',
    );
    expect(
      const MobileAlertReadiness(
        firebaseReady: true,
        tokenAvailable: true,
        permissionGranted: true,
        serverRegistered: true,
        channelExists: true,
        channelImportance: 2,
        channelSoundEnabled: true,
        channelVibrationEnabled: true,
      ).readinessMessage,
      'Registered, but urgent channel is muted',
    );
    expect(
      const MobileAlertReadiness(
        firebaseReady: true,
        tokenAvailable: true,
        permissionGranted: true,
        serverRegistered: true,
        channelExists: true,
        channelImportance: 4,
        channelSoundEnabled: true,
        channelVibrationEnabled: true,
      ).readinessMessage,
      'Ready for heads-up alerts',
    );
  });

  test('every widget provider is registered in AndroidManifest', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    for (final providerName in homeScreenWidgetProviderNames) {
      expect(manifest, contains('.$providerName'));
    }
  });

  test('manifest uses dedicated notification icon', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final service = File(
      'lib/features/mobile_alerts/data/mobile_alert_service.dart',
    ).readAsStringSync();

    expect(manifest, contains('@drawable/ic_homelab_notification'));
    expect(service, contains("icon: 'ic_homelab_notification'"));
    expect(
      File(
        'android/app/src/main/res/drawable/ic_homelab_notification.xml',
      ).existsSync(),
      isTrue,
    );
  });

  test('background handler skips notification-plus-data duplicate display', () {
    final service = File(
      'lib/features/mobile_alerts/data/mobile_alert_service.dart',
    ).readAsStringSync();

    expect(service, contains('if (message.notification != null)'));
    expect(service, contains('showVisibleNotificationFromMessage'));
  });

  test('every Add widget action has a provider target', () {
    expect(homeScreenWidgets.length, 6);
    expect(
      homeScreenWidgets.map((widget) => widget.providerName).toSet().length,
      homeScreenWidgets.length,
    );
    expect(
      homeScreenWidgetProviderNames,
      containsAll([
        serverEssentialsWidgetProviderName,
        compactStatusWidgetProviderName,
        performanceWidgetProviderName,
        storageHealthWidgetProviderName,
        networkActivityWidgetProviderName,
        quickAccessWidgetProviderName,
      ]),
    );
  });
}
