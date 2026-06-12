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
    );

    expect(payload['installation_id'], 'install-1234');
    expect(payload['platform'], 'android');
    expect(payload['enabled'], isTrue);
    expect(payload.containsKey('control_api_token'), isFalse);
    expect(payload.containsKey('firebase_service_account'), isFalse);
  });

  test('permission labels are clear', () {
    expect(MobileNotificationPermissionState.denied.label, 'Denied');
    expect(MobileNotificationPermissionState.granted.label, 'Granted');
  });

  test('every widget provider is registered in AndroidManifest', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    for (final providerName in homeScreenWidgetProviderNames) {
      expect(manifest, contains('.$providerName'));
    }
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
