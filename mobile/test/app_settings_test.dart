import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homelab_tablet/core/config/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('loadAppSettings maps existing keys into grouped settings', () async {
    SharedPreferences.setMockInitialValues({
      'onboardingComplete': true,
      'monitoringApiUrl': 'http://monitoring/api',
      'controlApiUrl': 'http://control/api',
      'summaryPollingMs': 1000,
      'detailsPollingMs': 3000,
      'healthPollingMs': 5000,
      'dockerPollingMs': 30000,
      'keepScreenAwakeOnOverview': true,
      'requirePrivilegedUnlock': false,
      'unlockTimeout': 'oneMinute',
      'ssh.displayName': 'Server SSH',
      'ssh.host': '100.64.10.22',
      'ssh.port': 22,
      'ssh.username': 'admin',
      'ssh.hasImportedKey': true,
      'ssh.storePassphrase': true,
      'sftp.displayName': 'Files',
      'sftp.host': '100.64.10.22',
      'sftp.port': 2022,
      'sftp.username': 'tablet',
      'sftp.hasImportedKey': true,
      'sftp.storePassphrase': true,
      'sftpVirtualRoot': '/warm',
      'allowSftpUpload': true,
      'allowSftpCreateDirectory': true,
      'allowSftpRename': true,
      'allowSftpMove': true,
      'allowSftpSoftDelete': true,
      'sftpBackgroundTimeout': 'fifteenMinutes',
      'widgetStorageMountpoint': '/mnt/storage',
      'widgetStorageLabel': 'Cold',
      'widgetSecondaryStorageMountpoint': '/mnt/warm',
      'widgetSecondaryStorageLabel': 'Warm',
      'widgetShowSecondaryStorage': true,
      'widgetBackgroundRefreshMinutes': 30,
      'widgetShowNetworkThroughput': true,
      'mobilePushAlertsEnabled': true,
      'mobilePushIncludeRecovery': false,
      'showRawApiErrors': true,
      'showRequestTiming': true,
    });

    final preferences = await SharedPreferences.getInstance();
    final settings = loadAppSettings(preferences);

    expect(settings.onboardingComplete, isTrue);
    expect(settings.monitoring.apiUrl, 'http://monitoring/api');
    expect(settings.monitoring.summaryPollingMs, 1000);
    expect(settings.control.apiUrl, 'http://control/api');
    expect(settings.tablet.keepScreenAwakeOnOverview, isTrue);
    expect(settings.tablet.requirePrivilegedUnlock, isFalse);
    expect(settings.tablet.unlockTimeout, PrivilegedUnlockTimeout.oneMinute);
    expect(settings.sshProfile.displayName, 'Server SSH');
    expect(settings.sshProfile.hasImportedKey, isTrue);
    expect(settings.sftp.profile.displayName, 'Files');
    expect(settings.sftp.profile.port, 2022);
    expect(settings.sftp.virtualRoot, '/warm');
    expect(settings.sftp.allowUpload, isTrue);
    expect(
      settings.sftp.backgroundTimeout,
      SftpBackgroundTimeout.fifteenMinutes,
    );
    expect(settings.widgets.storageMountpoint, '/mnt/storage');
    expect(settings.widgets.secondaryStorageMountpoint, '/mnt/warm');
    expect(settings.widgets.backgroundRefreshMinutes, 30);
    expect(settings.mobileAlerts.pushAlertsEnabled, isTrue);
    expect(settings.mobileAlerts.pushIncludeRecovery, isFalse);
    expect(settings.debug.showRawApiErrors, isTrue);
    expect(settings.debug.showRequestTiming, isTrue);

    expect(settings.monitoringApiUrl, settings.monitoring.apiUrl);
    expect(settings.sftpProfile, settings.sftp.profile);
    expect(settings.widgetStorageLabel, settings.widgets.storageLabel);
  });

  test('SettingsController saves grouped settings to existing keys', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
    );
    addTearDown(container.dispose);

    final controller = container.read(settingsControllerProvider.notifier);
    controller.save(
      AppSettings.defaults().copyWith(
        monitoring: const MonitoringSettings(
          apiUrl: ' http://monitoring/api ',
          summaryPollingMs: 1000,
          detailsPollingMs: 3000,
          healthPollingMs: 5000,
          dockerPollingMs: 30000,
        ),
        control: const ControlSettings(apiUrl: ' http://control/api '),
        sftp: AppSettings.defaults().sftp.copyWith(
          virtualRoot: 'warm',
          backgroundTimeout: SftpBackgroundTimeout.thirtyMinutes,
        ),
        widgets: const WidgetSettings(
          storageMountpoint: 'mnt/storage',
          storageLabel: ' Cold ',
          secondaryStorageMountpoint: 'mnt/warm',
          secondaryStorageLabel: ' Warm ',
          showSecondaryStorage: true,
          backgroundRefreshMinutes: 60,
          showNetworkThroughput: true,
        ),
        mobileAlerts: const MobileAlertSettings(
          pushAlertsEnabled: true,
          pushIncludeRecovery: false,
        ),
        debug: const DebugSettings(
          showRawApiErrors: true,
          showRequestTiming: true,
        ),
      ),
    );

    expect(preferences.getString('monitoringApiUrl'), 'http://monitoring/api');
    expect(preferences.getString('controlApiUrl'), 'http://control/api');
    expect(preferences.getString('sftpVirtualRoot'), '/warm');
    expect(
      preferences.getString('sftpBackgroundTimeout'),
      SftpBackgroundTimeout.thirtyMinutes.name,
    );
    expect(preferences.getString('widgetStorageMountpoint'), '/mnt/storage');
    expect(preferences.getString('widgetStorageLabel'), 'Cold');
    expect(
      preferences.getString('widgetSecondaryStorageMountpoint'),
      '/mnt/warm',
    );
    expect(preferences.getString('widgetSecondaryStorageLabel'), 'Warm');
    expect(preferences.getBool('widgetShowSecondaryStorage'), isTrue);
    expect(preferences.getInt('widgetBackgroundRefreshMinutes'), 60);
    expect(preferences.getBool('widgetShowNetworkThroughput'), isTrue);
    expect(preferences.getBool('mobilePushAlertsEnabled'), isTrue);
    expect(preferences.getBool('mobilePushIncludeRecovery'), isFalse);
    expect(preferences.getBool('showRawApiErrors'), isTrue);
    expect(preferences.getBool('showRequestTiming'), isTrue);
  });
}
