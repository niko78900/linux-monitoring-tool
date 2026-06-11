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
    required this.monitoringApiUrl,
    required this.controlApiUrl,
    required this.summaryPollingMs,
    required this.detailsPollingMs,
    required this.healthPollingMs,
    required this.dockerPollingMs,
    required this.keepScreenAwakeOnOverview,
    required this.requirePrivilegedUnlock,
    required this.unlockTimeout,
    required this.sshProfile,
    required this.sftpProfile,
    required this.sftpVirtualRoot,
    required this.showRawApiErrors,
    required this.showRequestTiming,
  });

  factory AppSettings.defaults() {
    return const AppSettings(
      onboardingComplete: false,
      monitoringApiUrl: AppConfig.defaultMonitoringApiUrl,
      controlApiUrl: AppConfig.defaultControlApiUrl,
      summaryPollingMs: 5000,
      detailsPollingMs: 15000,
      healthPollingMs: 15000,
      dockerPollingMs: 30000,
      keepScreenAwakeOnOverview: false,
      requirePrivilegedUnlock: true,
      unlockTimeout: PrivilegedUnlockTimeout.fiveMinutes,
      sshProfile: ConnectionProfile.empty(kind: ConnectionProfileKind.ssh),
      sftpProfile: ConnectionProfile.empty(kind: ConnectionProfileKind.sftp),
      sftpVirtualRoot: '/warm',
      showRawApiErrors: false,
      showRequestTiming: false,
    );
  }

  final bool onboardingComplete;
  final String monitoringApiUrl;
  final String controlApiUrl;
  final int summaryPollingMs;
  final int detailsPollingMs;
  final int healthPollingMs;
  final int dockerPollingMs;
  final bool keepScreenAwakeOnOverview;
  final bool requirePrivilegedUnlock;
  final PrivilegedUnlockTimeout unlockTimeout;
  final ConnectionProfile sshProfile;
  final ConnectionProfile sftpProfile;
  final String sftpVirtualRoot;
  final bool showRawApiErrors;
  final bool showRequestTiming;

  AppSettings copyWith({
    bool? onboardingComplete,
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
    bool? showRawApiErrors,
    bool? showRequestTiming,
  }) {
    return AppSettings(
      onboardingComplete: onboardingComplete ?? this.onboardingComplete,
      monitoringApiUrl: monitoringApiUrl ?? this.monitoringApiUrl,
      controlApiUrl: controlApiUrl ?? this.controlApiUrl,
      summaryPollingMs: summaryPollingMs ?? this.summaryPollingMs,
      detailsPollingMs: detailsPollingMs ?? this.detailsPollingMs,
      healthPollingMs: healthPollingMs ?? this.healthPollingMs,
      dockerPollingMs: dockerPollingMs ?? this.dockerPollingMs,
      keepScreenAwakeOnOverview:
          keepScreenAwakeOnOverview ?? this.keepScreenAwakeOnOverview,
      requirePrivilegedUnlock:
          requirePrivilegedUnlock ?? this.requirePrivilegedUnlock,
      unlockTimeout: unlockTimeout ?? this.unlockTimeout,
      sshProfile: sshProfile ?? this.sshProfile,
      sftpProfile: sftpProfile ?? this.sftpProfile,
      sftpVirtualRoot: sftpVirtualRoot ?? this.sftpVirtualRoot,
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
    return _load(_preferences);
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
    );
    _write(state);
  }

  void completeOnboarding(AppSettings settings) {
    save(settings.copyWith(onboardingComplete: true));
  }

  void resetOnboarding() {
    save(state.copyWith(onboardingComplete: false));
  }

  static AppSettings _load(SharedPreferences preferences) {
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
          preferences.getInt(_Keys.summaryPollingMs) ??
          defaults.summaryPollingMs,
      detailsPollingMs:
          preferences.getInt(_Keys.detailsPollingMs) ??
          defaults.detailsPollingMs,
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
      showRawApiErrors:
          preferences.getBool(_Keys.showRawApiErrors) ??
          defaults.showRawApiErrors,
      showRequestTiming:
          preferences.getBool(_Keys.showRequestTiming) ??
          defaults.showRequestTiming,
    );
  }

  static ConnectionProfile _loadProfile(
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
          preferences.getString('$prefix.${_Keys.profileHost}') ??
          defaults.host,
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
  static const showRawApiErrors = 'showRawApiErrors';
  static const showRequestTiming = 'showRequestTiming';
  static const profileName = 'displayName';
  static const profileHost = 'host';
  static const profilePort = 'port';
  static const profileUsername = 'username';
  static const profileHasKey = 'hasImportedKey';
  static const profileStorePassphrase = 'storePassphrase';
}
