import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_config.dart';

final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('SharedPreferences must be overridden.'),
);

final settingsControllerProvider =
    NotifierProvider<SettingsController, AppSettings>(SettingsController.new);

class AppSettings {
  const AppSettings({
    required this.onboardingComplete,
    required this.monitoring,
    required this.control,
    required this.tablet,
    required this.sshProfile,
    required this.sftp,
    required this.widgets,
    required this.mobileAlerts,
    required this.debug,
  });

  factory AppSettings.defaults() {
    return const AppSettings(
      onboardingComplete: false,
      monitoring: MonitoringSettings(
        apiUrl: AppConfig.defaultMonitoringApiUrl,
        summaryPollingMs: 5000,
        detailsPollingMs: 15000,
        healthPollingMs: 15000,
        dockerPollingMs: 30000,
      ),
      control: ControlSettings(apiUrl: AppConfig.defaultControlApiUrl),
      tablet: TabletSettings(
        keepScreenAwakeOnOverview: false,
        requirePrivilegedUnlock: true,
        unlockTimeout: PrivilegedUnlockTimeout.fiveMinutes,
      ),
      sshProfile: ConnectionProfile.empty(kind: ConnectionProfileKind.ssh),
      sftp: SftpSettings(
        profile: ConnectionProfile.empty(kind: ConnectionProfileKind.sftp),
        virtualRoot: '/warm',
        allowUpload: false,
        allowCreateDirectory: false,
        allowRename: false,
        allowMove: false,
        allowSoftDelete: false,
        backgroundTimeout: SftpBackgroundTimeout.fiveMinutes,
      ),
      widgets: WidgetSettings(
        storageMountpoint: '/mnt/storage',
        storageLabel: 'Cold Storage',
        secondaryStorageMountpoint: '/mnt/warm',
        secondaryStorageLabel: 'Warm Storage',
        showSecondaryStorage: false,
        backgroundRefreshMinutes: 15,
        showNetworkThroughput: false,
      ),
      mobileAlerts: MobileAlertSettings(
        pushAlertsEnabled: false,
        pushIncludeRecovery: true,
      ),
      debug: DebugSettings(showRawApiErrors: false, showRequestTiming: false),
    );
  }

  final bool onboardingComplete;
  final MonitoringSettings monitoring;
  final ControlSettings control;
  final TabletSettings tablet;
  final ConnectionProfile sshProfile;
  final SftpSettings sftp;
  final WidgetSettings widgets;
  final MobileAlertSettings mobileAlerts;
  final DebugSettings debug;

  String get monitoringApiUrl => monitoring.apiUrl;
  String get controlApiUrl => control.apiUrl;
  int get summaryPollingMs => monitoring.summaryPollingMs;
  int get detailsPollingMs => monitoring.detailsPollingMs;
  int get healthPollingMs => monitoring.healthPollingMs;
  int get dockerPollingMs => monitoring.dockerPollingMs;
  bool get keepScreenAwakeOnOverview => tablet.keepScreenAwakeOnOverview;
  bool get requirePrivilegedUnlock => tablet.requirePrivilegedUnlock;
  PrivilegedUnlockTimeout get unlockTimeout => tablet.unlockTimeout;
  ConnectionProfile get sftpProfile => sftp.profile;
  String get sftpVirtualRoot => sftp.virtualRoot;
  bool get allowSftpUpload => sftp.allowUpload;
  bool get allowSftpCreateDirectory => sftp.allowCreateDirectory;
  bool get allowSftpRename => sftp.allowRename;
  bool get allowSftpMove => sftp.allowMove;
  bool get allowSftpSoftDelete => sftp.allowSoftDelete;
  SftpBackgroundTimeout get sftpBackgroundTimeout => sftp.backgroundTimeout;
  String get widgetStorageMountpoint => widgets.storageMountpoint;
  String get widgetStorageLabel => widgets.storageLabel;
  String get widgetSecondaryStorageMountpoint =>
      widgets.secondaryStorageMountpoint;
  String get widgetSecondaryStorageLabel => widgets.secondaryStorageLabel;
  bool get widgetShowSecondaryStorage => widgets.showSecondaryStorage;
  int get widgetBackgroundRefreshMinutes => widgets.backgroundRefreshMinutes;
  bool get widgetShowNetworkThroughput => widgets.showNetworkThroughput;
  bool get mobilePushAlertsEnabled => mobileAlerts.pushAlertsEnabled;
  bool get mobilePushIncludeRecovery => mobileAlerts.pushIncludeRecovery;
  bool get showRawApiErrors => debug.showRawApiErrors;
  bool get showRequestTiming => debug.showRequestTiming;

  AppSettings copyWith({
    bool? onboardingComplete,
    MonitoringSettings? monitoring,
    ControlSettings? control,
    TabletSettings? tablet,
    SftpSettings? sftp,
    WidgetSettings? widgets,
    MobileAlertSettings? mobileAlerts,
    DebugSettings? debug,
    String? monitoringApiUrl,
    String? controlApiUrl,
    int? summaryPollingMs,
    int? detailsPollingMs,
    int? healthPollingMs,
    int? dockerPollingMs,
    bool? keepScreenAwakeOnOverview,
    bool? requirePrivilegedUnlock,
    PrivilegedUnlockTimeout? unlockTimeout,
    ConnectionProfile? sshProfile,
    ConnectionProfile? sftpProfile,
    String? sftpVirtualRoot,
    bool? allowSftpUpload,
    bool? allowSftpCreateDirectory,
    bool? allowSftpRename,
    bool? allowSftpMove,
    bool? allowSftpSoftDelete,
    SftpBackgroundTimeout? sftpBackgroundTimeout,
    String? widgetStorageMountpoint,
    String? widgetStorageLabel,
    String? widgetSecondaryStorageMountpoint,
    String? widgetSecondaryStorageLabel,
    bool? widgetShowSecondaryStorage,
    int? widgetBackgroundRefreshMinutes,
    bool? widgetShowNetworkThroughput,
    bool? mobilePushAlertsEnabled,
    bool? mobilePushIncludeRecovery,
    bool? showRawApiErrors,
    bool? showRequestTiming,
  }) {
    return AppSettings(
      onboardingComplete: onboardingComplete ?? this.onboardingComplete,
      monitoring:
          monitoring ??
          this.monitoring.copyWith(
            apiUrl: monitoringApiUrl,
            summaryPollingMs: summaryPollingMs,
            detailsPollingMs: detailsPollingMs,
            healthPollingMs: healthPollingMs,
            dockerPollingMs: dockerPollingMs,
          ),
      control: control ?? this.control.copyWith(apiUrl: controlApiUrl),
      tablet:
          tablet ??
          this.tablet.copyWith(
            keepScreenAwakeOnOverview: keepScreenAwakeOnOverview,
            requirePrivilegedUnlock: requirePrivilegedUnlock,
            unlockTimeout: unlockTimeout,
          ),
      sshProfile: sshProfile ?? this.sshProfile,
      sftp:
          sftp ??
          this.sftp.copyWith(
            profile: sftpProfile,
            virtualRoot: sftpVirtualRoot,
            allowUpload: allowSftpUpload,
            allowCreateDirectory: allowSftpCreateDirectory,
            allowRename: allowSftpRename,
            allowMove: allowSftpMove,
            allowSoftDelete: allowSftpSoftDelete,
            backgroundTimeout: sftpBackgroundTimeout,
          ),
      widgets:
          widgets ??
          this.widgets.copyWith(
            storageMountpoint: widgetStorageMountpoint,
            storageLabel: widgetStorageLabel,
            secondaryStorageMountpoint: widgetSecondaryStorageMountpoint,
            secondaryStorageLabel: widgetSecondaryStorageLabel,
            showSecondaryStorage: widgetShowSecondaryStorage,
            backgroundRefreshMinutes: widgetBackgroundRefreshMinutes,
            showNetworkThroughput: widgetShowNetworkThroughput,
          ),
      mobileAlerts:
          mobileAlerts ??
          this.mobileAlerts.copyWith(
            pushAlertsEnabled: mobilePushAlertsEnabled,
            pushIncludeRecovery: mobilePushIncludeRecovery,
          ),
      debug:
          debug ??
          this.debug.copyWith(
            showRawApiErrors: showRawApiErrors,
            showRequestTiming: showRequestTiming,
          ),
    );
  }
}

class MonitoringSettings {
  const MonitoringSettings({
    required this.apiUrl,
    required this.summaryPollingMs,
    required this.detailsPollingMs,
    required this.healthPollingMs,
    required this.dockerPollingMs,
  });

  final String apiUrl;
  final int summaryPollingMs;
  final int detailsPollingMs;
  final int healthPollingMs;
  final int dockerPollingMs;

  MonitoringSettings copyWith({
    String? apiUrl,
    int? summaryPollingMs,
    int? detailsPollingMs,
    int? healthPollingMs,
    int? dockerPollingMs,
  }) {
    return MonitoringSettings(
      apiUrl: apiUrl ?? this.apiUrl,
      summaryPollingMs: summaryPollingMs ?? this.summaryPollingMs,
      detailsPollingMs: detailsPollingMs ?? this.detailsPollingMs,
      healthPollingMs: healthPollingMs ?? this.healthPollingMs,
      dockerPollingMs: dockerPollingMs ?? this.dockerPollingMs,
    );
  }
}

class ControlSettings {
  const ControlSettings({required this.apiUrl});

  final String apiUrl;

  ControlSettings copyWith({String? apiUrl}) {
    return ControlSettings(apiUrl: apiUrl ?? this.apiUrl);
  }
}

class TabletSettings {
  const TabletSettings({
    required this.keepScreenAwakeOnOverview,
    required this.requirePrivilegedUnlock,
    required this.unlockTimeout,
  });

  final bool keepScreenAwakeOnOverview;
  final bool requirePrivilegedUnlock;
  final PrivilegedUnlockTimeout unlockTimeout;

  TabletSettings copyWith({
    bool? keepScreenAwakeOnOverview,
    bool? requirePrivilegedUnlock,
    PrivilegedUnlockTimeout? unlockTimeout,
  }) {
    return TabletSettings(
      keepScreenAwakeOnOverview:
          keepScreenAwakeOnOverview ?? this.keepScreenAwakeOnOverview,
      requirePrivilegedUnlock:
          requirePrivilegedUnlock ?? this.requirePrivilegedUnlock,
      unlockTimeout: unlockTimeout ?? this.unlockTimeout,
    );
  }
}

class SftpSettings {
  const SftpSettings({
    required this.profile,
    required this.virtualRoot,
    required this.allowUpload,
    required this.allowCreateDirectory,
    required this.allowRename,
    required this.allowMove,
    required this.allowSoftDelete,
    required this.backgroundTimeout,
  });

  final ConnectionProfile profile;
  final String virtualRoot;
  final bool allowUpload;
  final bool allowCreateDirectory;
  final bool allowRename;
  final bool allowMove;
  final bool allowSoftDelete;
  final SftpBackgroundTimeout backgroundTimeout;

  SftpSettings copyWith({
    ConnectionProfile? profile,
    String? virtualRoot,
    bool? allowUpload,
    bool? allowCreateDirectory,
    bool? allowRename,
    bool? allowMove,
    bool? allowSoftDelete,
    SftpBackgroundTimeout? backgroundTimeout,
  }) {
    return SftpSettings(
      profile: profile ?? this.profile,
      virtualRoot: virtualRoot ?? this.virtualRoot,
      allowUpload: allowUpload ?? this.allowUpload,
      allowCreateDirectory: allowCreateDirectory ?? this.allowCreateDirectory,
      allowRename: allowRename ?? this.allowRename,
      allowMove: allowMove ?? this.allowMove,
      allowSoftDelete: allowSoftDelete ?? this.allowSoftDelete,
      backgroundTimeout: backgroundTimeout ?? this.backgroundTimeout,
    );
  }
}

class WidgetSettings {
  const WidgetSettings({
    required this.storageMountpoint,
    required this.storageLabel,
    required this.secondaryStorageMountpoint,
    required this.secondaryStorageLabel,
    required this.showSecondaryStorage,
    required this.backgroundRefreshMinutes,
    required this.showNetworkThroughput,
  });

  final String storageMountpoint;
  final String storageLabel;
  final String secondaryStorageMountpoint;
  final String secondaryStorageLabel;
  final bool showSecondaryStorage;
  final int backgroundRefreshMinutes;
  final bool showNetworkThroughput;

  WidgetSettings copyWith({
    String? storageMountpoint,
    String? storageLabel,
    String? secondaryStorageMountpoint,
    String? secondaryStorageLabel,
    bool? showSecondaryStorage,
    int? backgroundRefreshMinutes,
    bool? showNetworkThroughput,
  }) {
    return WidgetSettings(
      storageMountpoint: storageMountpoint ?? this.storageMountpoint,
      storageLabel: storageLabel ?? this.storageLabel,
      secondaryStorageMountpoint:
          secondaryStorageMountpoint ?? this.secondaryStorageMountpoint,
      secondaryStorageLabel:
          secondaryStorageLabel ?? this.secondaryStorageLabel,
      showSecondaryStorage: showSecondaryStorage ?? this.showSecondaryStorage,
      backgroundRefreshMinutes:
          backgroundRefreshMinutes ?? this.backgroundRefreshMinutes,
      showNetworkThroughput:
          showNetworkThroughput ?? this.showNetworkThroughput,
    );
  }
}

class MobileAlertSettings {
  const MobileAlertSettings({
    required this.pushAlertsEnabled,
    required this.pushIncludeRecovery,
  });

  final bool pushAlertsEnabled;
  final bool pushIncludeRecovery;

  MobileAlertSettings copyWith({
    bool? pushAlertsEnabled,
    bool? pushIncludeRecovery,
  }) {
    return MobileAlertSettings(
      pushAlertsEnabled: pushAlertsEnabled ?? this.pushAlertsEnabled,
      pushIncludeRecovery: pushIncludeRecovery ?? this.pushIncludeRecovery,
    );
  }
}

class DebugSettings {
  const DebugSettings({
    required this.showRawApiErrors,
    required this.showRequestTiming,
  });

  final bool showRawApiErrors;
  final bool showRequestTiming;

  DebugSettings copyWith({bool? showRawApiErrors, bool? showRequestTiming}) {
    return DebugSettings(
      showRawApiErrors: showRawApiErrors ?? this.showRawApiErrors,
      showRequestTiming: showRequestTiming ?? this.showRequestTiming,
    );
  }
}

enum PrivilegedUnlockTimeout {
  immediately(0, 'Immediately'),
  oneMinute(60, '1 minute'),
  fiveMinutes(300, '5 minutes'),
  fifteenMinutes(900, '15 minutes');

  const PrivilegedUnlockTimeout(this.seconds, this.label);

  final int seconds;
  final String label;

  Duration get duration => Duration(seconds: seconds);

  static PrivilegedUnlockTimeout fromName(String? name) {
    return PrivilegedUnlockTimeout.values.firstWhere(
      (value) => value.name == name,
      orElse: () => PrivilegedUnlockTimeout.fiveMinutes,
    );
  }
}

enum SftpBackgroundTimeout {
  immediate('Disconnect immediately', null),
  oneMinute('1 minute', Duration(minutes: 1)),
  fiveMinutes('5 minutes', Duration(minutes: 5)),
  fifteenMinutes('15 minutes', Duration(minutes: 15)),
  thirtyMinutes('30 minutes', Duration(minutes: 30)),
  manual('Keep until manually disconnected', null);

  const SftpBackgroundTimeout(this.label, this.duration);

  final String label;
  final Duration? duration;

  static SftpBackgroundTimeout fromName(String? name) {
    return SftpBackgroundTimeout.values.firstWhere(
      (value) => value.name == name,
      orElse: () => SftpBackgroundTimeout.fiveMinutes,
    );
  }
}

enum ConnectionProfileKind { ssh, sftp }

class ConnectionProfile {
  const ConnectionProfile({
    required this.kind,
    required this.displayName,
    required this.host,
    required this.port,
    required this.username,
    required this.hasImportedKey,
    required this.storePassphrase,
  });

  const ConnectionProfile.empty({required this.kind})
    : displayName = '',
      host = '',
      port = AppConfig.defaultSshPort,
      username = '',
      hasImportedKey = false,
      storePassphrase = false;

  final ConnectionProfileKind kind;
  final String displayName;
  final String host;
  final int port;
  final String username;
  final bool hasImportedKey;
  final bool storePassphrase;

  ConnectionProfile copyWith({
    String? displayName,
    String? host,
    int? port,
    String? username,
    bool? hasImportedKey,
    bool? storePassphrase,
  }) {
    return ConnectionProfile(
      kind: kind,
      displayName: displayName ?? this.displayName,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      hasImportedKey: hasImportedKey ?? this.hasImportedKey,
      storePassphrase: storePassphrase ?? this.storePassphrase,
    );
  }

  bool get isConfigured =>
      host.trim().isNotEmpty && username.trim().isNotEmpty && port > 0;
}

class SettingsController extends Notifier<AppSettings> {
  late SharedPreferences _preferences;

  @override
  AppSettings build() {
    _preferences = ref.watch(sharedPreferencesProvider);
    return loadAppSettings(_preferences);
  }

  void save(AppSettings settings) {
    state = settings.copyWith(
      monitoringApiUrl: settings.monitoringApiUrl.trim(),
      controlApiUrl: settings.controlApiUrl.trim(),
      sftpVirtualRoot: _normalizeRoot(settings.sftpVirtualRoot),
      summaryPollingMs: _clampPolling(settings.summaryPollingMs),
      detailsPollingMs: _clampPolling(settings.detailsPollingMs),
      healthPollingMs: _clampPolling(settings.healthPollingMs),
      dockerPollingMs: _clampPolling(settings.dockerPollingMs),
      widgetStorageMountpoint: _normalizeWidgetMountpoint(
        settings.widgetStorageMountpoint,
      ),
      widgetStorageLabel: _normalizeWidgetLabel(
        settings.widgetStorageLabel,
        fallback: 'Primary Storage',
      ),
      widgetSecondaryStorageMountpoint: _normalizeWidgetMountpoint(
        settings.widgetSecondaryStorageMountpoint,
      ),
      widgetSecondaryStorageLabel: _normalizeWidgetLabel(
        settings.widgetSecondaryStorageLabel,
        fallback: 'Secondary Storage',
      ),
      widgetBackgroundRefreshMinutes: normalizeWidgetRefreshMinutes(
        settings.widgetBackgroundRefreshMinutes,
      ),
    );
    _write(state);
  }

  void completeOnboarding(AppSettings settings) {
    save(settings.copyWith(onboardingComplete: true));
  }

  void resetOnboarding() {
    save(state.copyWith(onboardingComplete: false));
  }

  void _write(AppSettings settings) {
    _preferences.setBool(_Keys.onboardingComplete, settings.onboardingComplete);
    _preferences.setString(_Keys.monitoringApiUrl, settings.monitoringApiUrl);
    _preferences.setString(_Keys.controlApiUrl, settings.controlApiUrl);
    _preferences.setInt(_Keys.summaryPollingMs, settings.summaryPollingMs);
    _preferences.setInt(_Keys.detailsPollingMs, settings.detailsPollingMs);
    _preferences.setInt(_Keys.healthPollingMs, settings.healthPollingMs);
    _preferences.setInt(_Keys.dockerPollingMs, settings.dockerPollingMs);
    _preferences.setBool(_Keys.keepAwake, settings.keepScreenAwakeOnOverview);
    _preferences.setBool(_Keys.requireUnlock, settings.requirePrivilegedUnlock);
    _preferences.setString(_Keys.unlockTimeout, settings.unlockTimeout.name);
    _preferences.setString(_Keys.sftpVirtualRoot, settings.sftpVirtualRoot);
    _preferences.setBool(_Keys.allowSftpUpload, settings.allowSftpUpload);
    _preferences.setBool(
      _Keys.allowSftpCreateDirectory,
      settings.allowSftpCreateDirectory,
    );
    _preferences.setBool(_Keys.allowSftpRename, settings.allowSftpRename);
    _preferences.setBool(_Keys.allowSftpMove, settings.allowSftpMove);
    _preferences.setBool(
      _Keys.allowSftpSoftDelete,
      settings.allowSftpSoftDelete,
    );
    _preferences.setString(
      _Keys.sftpBackgroundTimeout,
      settings.sftpBackgroundTimeout.name,
    );
    _preferences.setString(
      _Keys.widgetStorageMountpoint,
      settings.widgetStorageMountpoint,
    );
    _preferences.setString(
      _Keys.widgetStorageLabel,
      settings.widgetStorageLabel,
    );
    _preferences.setString(
      _Keys.widgetSecondaryStorageMountpoint,
      settings.widgetSecondaryStorageMountpoint,
    );
    _preferences.setString(
      _Keys.widgetSecondaryStorageLabel,
      settings.widgetSecondaryStorageLabel,
    );
    _preferences.setBool(
      _Keys.widgetShowSecondaryStorage,
      settings.widgetShowSecondaryStorage,
    );
    _preferences.setInt(
      _Keys.widgetBackgroundRefreshMinutes,
      settings.widgetBackgroundRefreshMinutes,
    );
    _preferences.setBool(
      _Keys.widgetShowNetworkThroughput,
      settings.widgetShowNetworkThroughput,
    );
    _preferences.setBool(
      _Keys.mobilePushAlertsEnabled,
      settings.mobilePushAlertsEnabled,
    );
    _preferences.setBool(
      _Keys.mobilePushIncludeRecovery,
      settings.mobilePushIncludeRecovery,
    );
    _preferences.setBool(_Keys.showRawApiErrors, settings.showRawApiErrors);
    _preferences.setBool(_Keys.showRequestTiming, settings.showRequestTiming);
    _writeProfile(settings.sshProfile);
    _writeProfile(settings.sftpProfile);
  }

  void _writeProfile(ConnectionProfile profile) {
    final prefix = profile.kind.name;
    _preferences.setString('$prefix.${_Keys.profileName}', profile.displayName);
    _preferences.setString('$prefix.${_Keys.profileHost}', profile.host);
    _preferences.setInt('$prefix.${_Keys.profilePort}', profile.port);
    _preferences.setString(
      '$prefix.${_Keys.profileUsername}',
      profile.username,
    );
    _preferences.setBool(
      '$prefix.${_Keys.profileHasKey}',
      profile.hasImportedKey,
    );
    _preferences.setBool(
      '$prefix.${_Keys.profileStorePassphrase}',
      profile.storePassphrase,
    );
  }

  static int _clampPolling(int value) {
    return value.clamp(AppConfig.minPollingMs, AppConfig.maxPollingMs);
  }

  static String _normalizeRoot(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return '/warm';
    }
    return trimmed.startsWith('/') ? trimmed : '/$trimmed';
  }
}

AppSettings loadAppSettings(SharedPreferences preferences) {
  final defaults = AppSettings.defaults();
  return defaults.copyWith(
    onboardingComplete:
        preferences.getBool(_Keys.onboardingComplete) ??
        defaults.onboardingComplete,
    monitoringApiUrl:
        preferences.getString(_Keys.monitoringApiUrl) ??
        defaults.monitoringApiUrl,
    controlApiUrl:
        preferences.getString(_Keys.controlApiUrl) ?? defaults.controlApiUrl,
    summaryPollingMs:
        preferences.getInt(_Keys.summaryPollingMs) ?? defaults.summaryPollingMs,
    detailsPollingMs:
        preferences.getInt(_Keys.detailsPollingMs) ?? defaults.detailsPollingMs,
    healthPollingMs:
        preferences.getInt(_Keys.healthPollingMs) ?? defaults.healthPollingMs,
    dockerPollingMs:
        preferences.getInt(_Keys.dockerPollingMs) ?? defaults.dockerPollingMs,
    keepScreenAwakeOnOverview:
        preferences.getBool(_Keys.keepAwake) ??
        defaults.keepScreenAwakeOnOverview,
    requirePrivilegedUnlock:
        preferences.getBool(_Keys.requireUnlock) ??
        defaults.requirePrivilegedUnlock,
    unlockTimeout: PrivilegedUnlockTimeout.fromName(
      preferences.getString(_Keys.unlockTimeout),
    ),
    sshProfile: _loadProfile(
      preferences,
      ConnectionProfileKind.ssh,
      defaults.sshProfile,
    ),
    sftpProfile: _loadProfile(
      preferences,
      ConnectionProfileKind.sftp,
      defaults.sftpProfile.copyWith(port: AppConfig.defaultSftpPort),
    ),
    sftpVirtualRoot:
        preferences.getString(_Keys.sftpVirtualRoot) ??
        defaults.sftpVirtualRoot,
    allowSftpUpload:
        preferences.getBool(_Keys.allowSftpUpload) ?? defaults.allowSftpUpload,
    allowSftpCreateDirectory:
        preferences.getBool(_Keys.allowSftpCreateDirectory) ??
        defaults.allowSftpCreateDirectory,
    allowSftpRename:
        preferences.getBool(_Keys.allowSftpRename) ?? defaults.allowSftpRename,
    allowSftpMove:
        preferences.getBool(_Keys.allowSftpMove) ?? defaults.allowSftpMove,
    allowSftpSoftDelete:
        preferences.getBool(_Keys.allowSftpSoftDelete) ??
        defaults.allowSftpSoftDelete,
    sftpBackgroundTimeout: SftpBackgroundTimeout.fromName(
      preferences.getString(_Keys.sftpBackgroundTimeout),
    ),
    widgetStorageMountpoint:
        preferences.getString(_Keys.widgetStorageMountpoint) ??
        defaults.widgetStorageMountpoint,
    widgetStorageLabel:
        preferences.getString(_Keys.widgetStorageLabel) ??
        defaults.widgetStorageLabel,
    widgetSecondaryStorageMountpoint:
        preferences.getString(_Keys.widgetSecondaryStorageMountpoint) ??
        defaults.widgetSecondaryStorageMountpoint,
    widgetSecondaryStorageLabel:
        preferences.getString(_Keys.widgetSecondaryStorageLabel) ??
        defaults.widgetSecondaryStorageLabel,
    widgetShowSecondaryStorage:
        preferences.getBool(_Keys.widgetShowSecondaryStorage) ??
        defaults.widgetShowSecondaryStorage,
    widgetBackgroundRefreshMinutes: normalizeWidgetRefreshMinutes(
      preferences.getInt(_Keys.widgetBackgroundRefreshMinutes) ??
          defaults.widgetBackgroundRefreshMinutes,
    ),
    widgetShowNetworkThroughput:
        preferences.getBool(_Keys.widgetShowNetworkThroughput) ??
        defaults.widgetShowNetworkThroughput,
    mobilePushAlertsEnabled:
        preferences.getBool(_Keys.mobilePushAlertsEnabled) ??
        defaults.mobilePushAlertsEnabled,
    mobilePushIncludeRecovery:
        preferences.getBool(_Keys.mobilePushIncludeRecovery) ??
        defaults.mobilePushIncludeRecovery,
    showRawApiErrors:
        preferences.getBool(_Keys.showRawApiErrors) ??
        defaults.showRawApiErrors,
    showRequestTiming:
        preferences.getBool(_Keys.showRequestTiming) ??
        defaults.showRequestTiming,
  );
}

ConnectionProfile _loadProfile(
  SharedPreferences preferences,
  ConnectionProfileKind kind,
  ConnectionProfile defaults,
) {
  final prefix = kind.name;
  return ConnectionProfile(
    kind: kind,
    displayName:
        preferences.getString('$prefix.${_Keys.profileName}') ??
        defaults.displayName,
    host:
        preferences.getString('$prefix.${_Keys.profileHost}') ?? defaults.host,
    port: preferences.getInt('$prefix.${_Keys.profilePort}') ?? defaults.port,
    username:
        preferences.getString('$prefix.${_Keys.profileUsername}') ??
        defaults.username,
    hasImportedKey:
        preferences.getBool('$prefix.${_Keys.profileHasKey}') ??
        defaults.hasImportedKey,
    storePassphrase:
        preferences.getBool('$prefix.${_Keys.profileStorePassphrase}') ??
        defaults.storePassphrase,
  );
}

int normalizeWidgetRefreshMinutes(int value) {
  if (const {15, 30, 60}.contains(value)) {
    return value;
  }
  return 15;
}

String _normalizeWidgetMountpoint(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return '/mnt/storage';
  }
  return trimmed.startsWith('/') ? trimmed : '/$trimmed';
}

String _normalizeWidgetLabel(String value, {required String fallback}) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? fallback : trimmed;
}

class _Keys {
  static const onboardingComplete = 'onboardingComplete';
  static const monitoringApiUrl = 'monitoringApiUrl';
  static const controlApiUrl = 'controlApiUrl';
  static const summaryPollingMs = 'summaryPollingMs';
  static const detailsPollingMs = 'detailsPollingMs';
  static const healthPollingMs = 'healthPollingMs';
  static const dockerPollingMs = 'dockerPollingMs';
  static const keepAwake = 'keepScreenAwakeOnOverview';
  static const requireUnlock = 'requirePrivilegedUnlock';
  static const unlockTimeout = 'unlockTimeout';
  static const sftpVirtualRoot = 'sftpVirtualRoot';
  static const allowSftpUpload = 'allowSftpUpload';
  static const allowSftpCreateDirectory = 'allowSftpCreateDirectory';
  static const allowSftpRename = 'allowSftpRename';
  static const allowSftpMove = 'allowSftpMove';
  static const allowSftpSoftDelete = 'allowSftpSoftDelete';
  static const sftpBackgroundTimeout = 'sftpBackgroundTimeout';
  static const widgetStorageMountpoint = 'widgetStorageMountpoint';
  static const widgetStorageLabel = 'widgetStorageLabel';
  static const widgetSecondaryStorageMountpoint =
      'widgetSecondaryStorageMountpoint';
  static const widgetSecondaryStorageLabel = 'widgetSecondaryStorageLabel';
  static const widgetShowSecondaryStorage = 'widgetShowSecondaryStorage';
  static const widgetBackgroundRefreshMinutes =
      'widgetBackgroundRefreshMinutes';
  static const widgetShowNetworkThroughput = 'widgetShowNetworkThroughput';
  static const mobilePushAlertsEnabled = 'mobilePushAlertsEnabled';
  static const mobilePushIncludeRecovery = 'mobilePushIncludeRecovery';
  static const showRawApiErrors = 'showRawApiErrors';
  static const showRequestTiming = 'showRequestTiming';
  static const profileName = 'displayName';
  static const profileHost = 'host';
  static const profilePort = 'port';
  static const profileUsername = 'username';
  static const profileHasKey = 'hasImportedKey';
  static const profileStorePassphrase = 'storePassphrase';
}
