import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';

import '../../../../core/config/app_settings.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/networking/dio_factory.dart';
import '../../../../core/security/app_lock_service.dart';
import '../../../../core/security/secure_storage_service.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../dashboard/data/monitoring_api_client.dart';
import '../../../files/data/sftp_connection_service.dart';
import '../../../mobile_alerts/data/mobile_alert_service.dart';
import '../../../mobile_alerts/domain/models/mobile_alert_models.dart';
import '../../../network/data/control_api_client.dart';
import '../../../server_widget/data/server_widget_service.dart';
import '../../../terminal/data/private_key_validation.dart';
import '../../../terminal/data/ssh_connection_service.dart';
import '../../../terminal/domain/models/ssh_connection_models.dart';
import '../../../terminal/presentation/widgets/terminal_connection_dialogs.dart';
import '../sections/control_agent_settings_section.dart';
import '../sections/debug_settings_section.dart';
import '../sections/files_settings_section.dart';
import '../sections/monitoring_settings_section.dart';
import '../sections/push_alerts_settings_section.dart';
import '../sections/tablet_settings_section.dart';
import '../sections/terminal_settings_section.dart';
import '../sections/widget_settings_section.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final _monitoringUrl = TextEditingController();
  final _controlUrl = TextEditingController();
  final _controlToken = TextEditingController();
  final _mobileAlertToken = TextEditingController();
  final _sshName = TextEditingController();
  final _sshHost = TextEditingController();
  final _sshPort = TextEditingController();
  final _sshUser = TextEditingController();
  final _sshPassphrase = TextEditingController();
  final _sftpName = TextEditingController();
  final _sftpHost = TextEditingController();
  final _sftpPort = TextEditingController();
  final _sftpUser = TextEditingController();
  final _sftpPassphrase = TextEditingController();
  final _sftpRoot = TextEditingController();
  final _widgetMountpoint = TextEditingController();
  final _widgetLabel = TextEditingController();
  final _widgetSecondaryMountpoint = TextEditingController();
  final _widgetSecondaryLabel = TextEditingController();
  bool _loaded = false;
  bool _testingSsh = false;
  bool _testingSftp = false;
  bool _mobileAlertBusy = false;
  String? _requestingWidgetPinProvider;
  MobileAlertStatus? _mobileAlertStatus;
  MobileNotificationPermissionState? _notificationPermission;
  MobileAlertReadiness? _mobileAlertReadiness;
  String? _mobileAlertStatusText;
  String? _sshKeySummary;
  String? _sshTrustedFingerprint;
  bool _sshPassphraseRemembered = false;
  String? _sftpKeySummary;
  String? _sftpTrustedFingerprint;
  bool _sftpPassphraseRemembered = false;

  @override
  void dispose() {
    _monitoringUrl.dispose();
    _controlUrl.dispose();
    _controlToken.dispose();
    _mobileAlertToken.dispose();
    _sshName.dispose();
    _sshHost.dispose();
    _sshPort.dispose();
    _sshUser.dispose();
    _sshPassphrase.dispose();
    _sftpName.dispose();
    _sftpHost.dispose();
    _sftpPort.dispose();
    _sftpUser.dispose();
    _sftpPassphrase.dispose();
    _sftpRoot.dispose();
    _widgetMountpoint.dispose();
    _widgetLabel.dispose();
    _widgetSecondaryMountpoint.dispose();
    _widgetSecondaryLabel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsControllerProvider);
    if (!_loaded) {
      _load(settings);
    }

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        MonitoringSettingsSection(
          settings: settings,
          monitoringUrlController: _monitoringUrl,
          onSave: _save,
          onTest: _testMonitoring,
        ),
        ControlAgentSettingsSection(
          settings: settings,
          controlUrlController: _controlUrl,
          controlTokenController: _controlToken,
          onSave: _saveControl,
          onTest: _testControl,
          onClearToken: _clearToken,
        ),
        TerminalSettingsSection(
          settings: settings,
          nameController: _sshName,
          hostController: _sshHost,
          portController: _sshPort,
          userController: _sshUser,
          keySummary: _sshKeySummary,
          trustedFingerprint: _sshTrustedFingerprint,
          passphraseRemembered: _sshPassphraseRemembered,
          testing: _testingSsh,
          onSaveProfiles: _saveProfiles,
          onSetPassphraseStorage: _setSshPassphraseStorage,
          onForgetPassphrase: _forgetSshPassphrase,
          onImportKey: _importSshKey,
          onPasteKey: _pasteSshKey,
          onRemoveKey: _removeSshKey,
          onTest: _testSsh,
          onResetTrustedFingerprint: _resetTrustedFingerprint,
        ),
        FilesSettingsSection(
          settings: settings,
          nameController: _sftpName,
          hostController: _sftpHost,
          portController: _sftpPort,
          userController: _sftpUser,
          rootController: _sftpRoot,
          keySummary: _sftpKeySummary,
          trustedFingerprint: _sftpTrustedFingerprint,
          passphraseRemembered: _sftpPassphraseRemembered,
          testing: _testingSftp,
          onSaveProfiles: _saveProfiles,
          onSave: _save,
          onSetPassphraseStorage: _setSftpPassphraseStorage,
          onForgetPassphrase: _forgetSftpPassphrase,
          onImportKey: _importSftpKey,
          onPasteKey: _pasteSftpKey,
          onRemoveKey: _removeSftpKey,
          onTest: _testSftp,
          onResetTrustedFingerprint: _resetSftpTrustedFingerprint,
        ),
        WidgetSettingsSection(
          settings: settings,
          mountpointController: _widgetMountpoint,
          labelController: _widgetLabel,
          secondaryMountpointController: _widgetSecondaryMountpoint,
          secondaryLabelController: _widgetSecondaryLabel,
          requestingWidgetPinProvider: _requestingWidgetPinProvider,
          onSave: _save,
          onRefreshSnapshots: _refreshWidgetSnapshots,
          onRequestPinWidget: _requestPinWidget,
        ),
        PushAlertsSettingsSection(
          settings: settings,
          tokenController: _mobileAlertToken,
          busy: _mobileAlertBusy,
          notificationPermission: _notificationPermission,
          readiness: _mobileAlertReadiness,
          registrationLabel: _registrationLabel(),
          channelReadinessLabel: _channelReadinessLabel(),
          statusText: _mobileAlertStatusText,
          onSaveToken: _saveMobileAlertToken,
          onClearToken: _clearMobileAlertToken,
          onEnable: _enablePushAlerts,
          onDisable: _disablePushAlerts,
          onSave: _save,
          onRefreshStatus: _refreshMobileAlertStatus,
          onRegister: _enablePushAlerts,
          onSendTest: _sendTestPush,
          onOpenAndroidNotificationSettings: () => unawaited(
            MobileAlertService.instance.openAndroidNotificationSettings(),
          ),
        ),
        TabletSettingsSection(
          settings: settings,
          onSave: _save,
          onManualLock: () =>
              ref.read(appLockControllerProvider.notifier).lock(),
        ),
        DebugSettingsSection(
          settings: settings,
          onSave: _save,
          onResetOnboarding: () =>
              ref.read(settingsControllerProvider.notifier).resetOnboarding(),
        ),
      ],
    );
  }

  void _load(AppSettings settings) {
    _loaded = true;
    _monitoringUrl.text = settings.monitoringApiUrl;
    _controlUrl.text = settings.controlApiUrl;
    _sshName.text = settings.sshProfile.displayName;
    _sshHost.text = settings.sshProfile.host;
    _sshPort.text = settings.sshProfile.port.toString();
    _sshUser.text = settings.sshProfile.username;
    _sftpName.text = settings.sftpProfile.displayName;
    _sftpHost.text = settings.sftpProfile.host;
    _sftpPort.text = settings.sftpProfile.port.toString();
    _sftpUser.text = settings.sftpProfile.username;
    _sftpRoot.text = settings.sftpVirtualRoot;
    _widgetMountpoint.text = settings.widgetStorageMountpoint;
    _widgetLabel.text = settings.widgetStorageLabel;
    _widgetSecondaryMountpoint.text = settings.widgetSecondaryStorageMountpoint;
    _widgetSecondaryLabel.text = settings.widgetSecondaryStorageLabel;
    final storage = ref.read(secureStorageServiceProvider);
    storage.readControlToken().then((value) {
      if (mounted && value != null && _controlToken.text.isEmpty) {
        _controlToken.text = value;
      }
    });
    storage.readMobileAlertToken().then((value) {
      if (mounted && value != null && _mobileAlertToken.text.isEmpty) {
        _mobileAlertToken.text = value;
      }
    });
    storage.readSshPassphrase().then((value) {
      if (mounted && value != null && _sshPassphrase.text.isEmpty) {
        _sshPassphrase.text = value;
      }
    });
    storage.readSftpPassphrase().then((value) {
      if (mounted && value != null && _sftpPassphrase.text.isEmpty) {
        _sftpPassphrase.text = value;
      }
    });
    _refreshSshSecretState(settings);
    _refreshSftpSecretState(settings);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_refreshMobileAlertStatus(settings));
      }
    });
  }

  void _save(AppSettings settings) {
    ref.read(settingsControllerProvider.notifier).save(settings);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Settings saved')));
  }

  Future<void> _saveControl(AppSettings settings) async {
    await ref
        .read(secureStorageServiceProvider)
        .writeControlToken(_controlToken.text);
    _save(settings.copyWith(controlApiUrl: _controlUrl.text));
  }

  void _saveProfiles(AppSettings settings) {
    final next = _buildSettingsFromFields(settings);
    ref.read(settingsControllerProvider.notifier).save(next);
    unawaited(_persistSshPassphrase(next));
    unawaited(_persistSftpPassphrase(next));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Settings saved')));
  }

  AppSettings _buildSettingsFromFields(AppSettings settings) {
    return settings.copyWith(
      sshProfile: settings.sshProfile.copyWith(
        displayName: _sshName.text,
        host: _sshHost.text,
        port: int.tryParse(_sshPort.text) ?? 22,
        username: _sshUser.text,
      ),
      sftpProfile: settings.sftpProfile.copyWith(
        displayName: _sftpName.text,
        host: _sftpHost.text,
        port: int.tryParse(_sftpPort.text) ?? 22,
        username: _sftpUser.text,
      ),
      sftpVirtualRoot: _sftpRoot.text,
    );
  }

  Future<void> _persistSshPassphrase(AppSettings settings) async {
    final storage = ref.read(secureStorageServiceProvider);
    final passphrase = _sshPassphrase.text.trim();
    if (!settings.sshProfile.storePassphrase) {
      await storage.clearSshPassphrase();
      return;
    }
    if (passphrase.isNotEmpty) {
      await storage.writeSshPassphrase(passphrase);
    }
  }

  Future<void> _setSshPassphraseStorage(
    AppSettings settings,
    bool enabled,
  ) async {
    final next = _buildSettingsFromFields(
      settings.copyWith(
        sshProfile: settings.sshProfile.copyWith(storePassphrase: enabled),
      ),
    );
    ref.read(settingsControllerProvider.notifier).save(next);
    await _persistSshPassphrase(next);
    if (!enabled) {
      _sshPassphrase.clear();
    }
    await _refreshSshSecretState(next);
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Settings saved')));
    }
  }

  Future<void> _persistSftpPassphrase(AppSettings settings) async {
    final storage = ref.read(secureStorageServiceProvider);
    final passphrase = _sftpPassphrase.text.trim();
    if (!settings.sftpProfile.storePassphrase) {
      await storage.clearSftpPassphrase();
      return;
    }
    if (passphrase.isNotEmpty) {
      await storage.writeSftpPassphrase(passphrase);
    }
  }

  Future<void> _setSftpPassphraseStorage(
    AppSettings settings,
    bool enabled,
  ) async {
    final next = _buildSettingsFromFields(
      settings.copyWith(
        sftpProfile: settings.sftpProfile.copyWith(storePassphrase: enabled),
      ),
    );
    ref.read(settingsControllerProvider.notifier).save(next);
    await _persistSftpPassphrase(next);
    if (!enabled) {
      _sftpPassphrase.clear();
    }
    await _refreshSftpSecretState(next);
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Settings saved')));
    }
  }

  Future<void> _forgetSshPassphrase(AppSettings settings) async {
    await ref.read(secureStorageServiceProvider).clearSshPassphrase();
    _sshPassphrase.clear();
    final next = _buildSettingsFromFields(
      settings.copyWith(
        sshProfile: settings.sshProfile.copyWith(storePassphrase: false),
      ),
    );
    ref.read(settingsControllerProvider.notifier).save(next);
    await _refreshSshSecretState(next);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('SSH key passphrase forgotten')),
      );
    }
  }

  Future<void> _forgetSftpPassphrase(AppSettings settings) async {
    await ref.read(secureStorageServiceProvider).clearSftpPassphrase();
    _sftpPassphrase.clear();
    final next = _buildSettingsFromFields(
      settings.copyWith(
        sftpProfile: settings.sftpProfile.copyWith(storePassphrase: false),
      ),
    );
    ref.read(settingsControllerProvider.notifier).save(next);
    await _refreshSftpSecretState(next);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('SFTP key passphrase forgotten')),
      );
    }
  }

  Future<void> _clearToken() async {
    await ref.read(secureStorageServiceProvider).clearControlToken();
    _controlToken.clear();
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Control token cleared')));
    }
  }

  Future<void> _saveMobileAlertToken() async {
    await ref
        .read(secureStorageServiceProvider)
        .writeMobileAlertToken(_mobileAlertToken.text);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mobile-alert backend token saved')),
      );
    }
  }

  Future<void> _clearMobileAlertToken() async {
    await ref.read(secureStorageServiceProvider).clearMobileAlertToken();
    _mobileAlertToken.clear();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mobile-alert backend token cleared')),
      );
    }
  }

  Future<void> _testMonitoring() async {
    try {
      final client = MonitoringApiClient(
        DioFactory.create(baseUrl: _monitoringUrl.text),
      );
      final health = await client.getHealth();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connected to ${health.appName} ${health.version}'),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Monitoring API unreachable')),
        );
      }
    }
  }

  Future<void> _testControl() async {
    try {
      final client = ControlApiClient(
        baseUrl: _controlUrl.text,
        token: _controlToken.text,
      );
      await client.getHealth();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Control agent reachable')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Control agent unreachable')),
        );
      }
    }
  }

  Future<void> _requestPinWidget(String providerName) async {
    if (!Platform.isAndroid) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Widget pinning is Android only')),
        );
      }
      return;
    }

    setState(() => _requestingWidgetPinProvider = providerName);
    try {
      final supported = await HomeWidget.isRequestPinWidgetSupported();
      if (supported != true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Launcher does not support pinning')),
          );
        }
        return;
      }
      await HomeWidget.requestPinWidget(name: providerName);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Widget add request sent')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to request widget pinning')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _requestingWidgetPinProvider = null);
      }
    }
  }

  Future<void> _refreshWidgetSnapshots() async {
    await ServerWidgetService.instance.runBackgroundRefreshTask();
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Widget refresh requested')));
    }
  }

  Future<void> _refreshMobileAlertStatus(AppSettings settings) async {
    setState(() => _mobileAlertBusy = true);
    try {
      final preferences = ref.read(sharedPreferencesProvider);
      final token = await ref
          .read(secureStorageServiceProvider)
          .readMobileAlertToken();
      final permission = await MobileAlertService.instance.permissionState();
      MobileAlertStatus? status;
      try {
        status = await MobileAlertService.instance.status(
          settings: settings,
          preferences: preferences,
          mobileAlertToken: token,
        );
      } catch (_) {
        status = null;
      }
      final readiness = await MobileAlertService.instance.readiness(
        serverStatus: status,
        permission: permission,
      );
      if (mounted) {
        setState(() {
          _notificationPermission = permission;
          _mobileAlertStatus = status;
          _mobileAlertReadiness = readiness;
          _mobileAlertStatusText = status == null
              ? 'Backend mobile-alert status unavailable'
              : readiness.readinessMessage;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _mobileAlertBusy = false);
      }
    }
  }

  Future<void> _enablePushAlerts(AppSettings settings) async {
    setState(() => _mobileAlertBusy = true);
    try {
      final preferences = ref.read(sharedPreferencesProvider);
      final token = await ref
          .read(secureStorageServiceProvider)
          .readMobileAlertToken();
      final permission = await MobileAlertService.instance.requestPermission();
      final status = await MobileAlertService.instance.register(
        settings: settings,
        preferences: preferences,
        mobileAlertToken: token,
      );
      final next = settings.copyWith(mobilePushAlertsEnabled: true);
      final readiness = await MobileAlertService.instance.readiness(
        serverStatus: status,
        permission: permission,
      );
      ref.read(settingsControllerProvider.notifier).save(next);
      if (mounted) {
        setState(() {
          _notificationPermission = permission;
          _mobileAlertStatus = status;
          _mobileAlertReadiness = readiness;
          _mobileAlertStatusText = readiness.readinessMessage;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Push alerts registered')));
      }
    } catch (error) {
      if (mounted) {
        setState(() => _mobileAlertStatusText = _describeError(error));
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_describeError(error))));
      }
    } finally {
      if (mounted) {
        setState(() => _mobileAlertBusy = false);
      }
    }
  }

  Future<void> _disablePushAlerts(AppSettings settings) async {
    setState(() => _mobileAlertBusy = true);
    try {
      final preferences = ref.read(sharedPreferencesProvider);
      final token = await ref
          .read(secureStorageServiceProvider)
          .readMobileAlertToken();
      final status = await MobileAlertService.instance.disable(
        settings: settings,
        preferences: preferences,
        mobileAlertToken: token,
      );
      final next = settings.copyWith(mobilePushAlertsEnabled: false);
      ref.read(settingsControllerProvider.notifier).save(next);
      if (mounted) {
        setState(() {
          _mobileAlertStatus = status;
          _mobileAlertStatusText = 'Push alerts disabled';
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Push alerts disabled')));
      }
    } catch (error) {
      if (mounted) {
        setState(() => _mobileAlertStatusText = _describeError(error));
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_describeError(error))));
      }
    } finally {
      if (mounted) {
        setState(() => _mobileAlertBusy = false);
      }
    }
  }

  Future<void> _sendTestPush(AppSettings settings) async {
    setState(() => _mobileAlertBusy = true);
    try {
      final preferences = ref.read(sharedPreferencesProvider);
      final token = await ref
          .read(secureStorageServiceProvider)
          .readMobileAlertToken();
      final permission = await MobileAlertService.instance.requestPermission();
      final result = await MobileAlertService.instance.sendRoundTripTest(
        settings: settings,
        preferences: preferences,
        mobileAlertToken: token,
      );
      final status = await MobileAlertService.instance.status(
        settings: settings,
        preferences: preferences,
        mobileAlertToken: token,
      );
      final readiness = await MobileAlertService.instance.readiness(
        serverStatus: status,
        permission: permission,
      );
      if (mounted) {
        setState(() {
          _notificationPermission = permission;
          _mobileAlertStatus = status;
          _mobileAlertReadiness = readiness;
          _mobileAlertStatusText = readiness.fullyReady
              ? 'Test notification requested (${result.sentCount} sent)'
              : readiness.readinessMessage;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Round-trip test notification sent')),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _mobileAlertStatusText = _describeError(error));
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_describeError(error))));
      }
    } finally {
      if (mounted) {
        setState(() => _mobileAlertBusy = false);
      }
    }
  }

  String _registrationLabel() {
    final status = _mobileAlertStatus;
    if (status == null) {
      return 'Not checked';
    }
    final registered = status.registered ? 'registered' : 'not registered';
    final configured = status.pushConfigured
        ? 'server configured'
        : 'server Firebase missing';
    final last = status.lastRegisteredAt == null
        ? 'never'
        : status.lastRegisteredAt!.toLocal().toString();
    return '$registered, $configured, last registration $last';
  }

  String _channelReadinessLabel() {
    final readiness = _mobileAlertReadiness;
    if (readiness == null) {
      return 'Not checked';
    }
    if (!readiness.channelExists) {
      return 'Urgent channel missing';
    }
    final sound = readiness.channelSoundEnabled ? 'sound on' : 'sound off';
    final vibration = readiness.channelVibrationEnabled
        ? 'vibration on'
        : 'vibration off';
    return 'importance ${readiness.channelImportance}, $sound, $vibration';
  }

  Future<void> _testSsh(AppSettings settings) async {
    final next = _buildSettingsFromFields(settings);
    ref.read(settingsControllerProvider.notifier).save(next);
    await _persistSshPassphrase(next);

    setState(() => _testingSsh = true);
    try {
      await ref
          .read(sshConnectionServiceProvider)
          .testConnection(
            profile: next.sshProfile,
            onTrustHost: (hostKey) => showHostTrustDialog(context, hostKey),
            onPassphraseRequired: () => _promptSshPassphrase(next),
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('SSH connection succeeded')),
        );
      }
      await _refreshSshSecretState(next);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_describeError(error))));
      }
    } finally {
      if (mounted) {
        setState(() => _testingSsh = false);
      }
    }
  }

  Future<void> _testSftp(AppSettings settings) async {
    final next = _buildSettingsFromFields(settings);
    ref.read(settingsControllerProvider.notifier).save(next);
    await _persistSftpPassphrase(next);

    setState(() => _testingSftp = true);
    try {
      await ref
          .read(sftpConnectionServiceProvider)
          .testConnection(
            profile: next.sftpProfile,
            onTrustHost: (hostKey) => showHostTrustDialog(context, hostKey),
            onPassphraseRequired: () => _promptSftpPassphrase(next),
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('SFTP connection succeeded')),
        );
      }
      await _refreshSftpSecretState(next);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_describeError(error))));
      }
    } finally {
      if (mounted) {
        setState(() => _testingSftp = false);
      }
    }
  }

  Future<PassphrasePromptResult?> _promptSshPassphrase(
    AppSettings settings,
  ) async {
    final result = await showPassphrasePromptDialog(
      context,
      title: 'Enter the SSH key passphrase',
      rememberInitially: settings.sshProfile.storePassphrase,
    );
    if (result == null) {
      return null;
    }

    final storage = ref.read(secureStorageServiceProvider);
    final next = _buildSettingsFromFields(
      settings.copyWith(
        sshProfile: settings.sshProfile.copyWith(
          storePassphrase: result.remember,
        ),
      ),
    );
    if (result.remember) {
      _sshPassphrase.text = result.passphrase;
      await storage.writeSshPassphrase(result.passphrase);
    } else {
      _sshPassphrase.clear();
      await storage.clearSshPassphrase();
    }
    ref.read(settingsControllerProvider.notifier).save(next);
    await _refreshSshSecretState(next);
    return result;
  }

  Future<PassphrasePromptResult?> _promptSftpPassphrase(
    AppSettings settings,
  ) async {
    final result = await showPassphrasePromptDialog(
      context,
      title: 'Enter the SFTP key passphrase',
      rememberInitially: settings.sftpProfile.storePassphrase,
    );
    if (result == null) {
      return null;
    }

    final storage = ref.read(secureStorageServiceProvider);
    final next = _buildSettingsFromFields(
      settings.copyWith(
        sftpProfile: settings.sftpProfile.copyWith(
          storePassphrase: result.remember,
        ),
      ),
    );
    if (result.remember) {
      _sftpPassphrase.text = result.passphrase;
      await storage.writeSftpPassphrase(result.passphrase);
    } else {
      _sftpPassphrase.clear();
      await storage.clearSftpPassphrase();
    }
    ref.read(settingsControllerProvider.notifier).save(next);
    await _refreshSftpSecretState(next);
    return result;
  }

  Future<void> _importSshKey(AppSettings settings) async {
    final result = await FilePicker.pickFiles(
      type: FileType.any,
      withData: true,
    );
    if (result == null || result.files.isEmpty) {
      return;
    }
    final file = result.files.single;
    String? contents;
    if (file.bytes != null) {
      contents = utf8.decode(file.bytes!, allowMalformed: true);
    } else if (file.path != null) {
      contents = await File(file.path!).readAsString();
    }
    if (contents == null || contents.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('The selected file was empty')),
        );
      }
      return;
    }
    await _storeSshKey(settings, contents);
  }

  Future<void> _pasteSshKey(AppSettings settings) async {
    final controller = TextEditingController();
    final contents = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Paste private key'),
          content: SizedBox(
            width: 560,
            child: TextField(
              controller: controller,
              autofocus: true,
              minLines: 12,
              maxLines: 16,
              decoration: const InputDecoration(
                alignLabelWithHint: true,
                labelText: 'PEM or OpenSSH private key',
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('Save key'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (contents == null || contents.trim().isEmpty) {
      return;
    }
    await _storeSshKey(settings, contents);
  }

  Future<void> _storeSshKey(AppSettings settings, String contents) async {
    late final String normalized;
    try {
      normalized = validateAndNormalizePrivateKey(contents);
    } on AppException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
      return;
    }
    await ref.read(secureStorageServiceProvider).writeSshPrivateKey(normalized);
    final next = _buildSettingsFromFields(
      settings.copyWith(
        sshProfile: settings.sshProfile.copyWith(hasImportedKey: true),
      ),
    );
    ref.read(settingsControllerProvider.notifier).save(next);
    await _persistSshPassphrase(next);
    await _refreshSshSecretState(next);
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('SSH private key saved')));
    }
  }

  Future<void> _importSftpKey(AppSettings settings) async {
    final result = await FilePicker.pickFiles(
      type: FileType.any,
      withData: true,
    );
    if (result == null || result.files.isEmpty) {
      return;
    }
    final file = result.files.single;
    String? contents;
    if (file.bytes != null) {
      contents = utf8.decode(file.bytes!, allowMalformed: true);
    } else if (file.path != null) {
      contents = await File(file.path!).readAsString();
    }
    if (contents == null || contents.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('The selected file was empty')),
        );
      }
      return;
    }
    await _storeSftpKey(settings, contents);
  }

  Future<void> _pasteSftpKey(AppSettings settings) async {
    final controller = TextEditingController();
    final contents = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Paste restricted SFTP key'),
          content: SizedBox(
            width: 560,
            child: TextField(
              controller: controller,
              autofocus: true,
              minLines: 12,
              maxLines: 16,
              decoration: const InputDecoration(
                alignLabelWithHint: true,
                labelText: 'PEM or OpenSSH private key',
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('Save key'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (contents == null || contents.trim().isEmpty) {
      return;
    }
    await _storeSftpKey(settings, contents);
  }

  Future<void> _storeSftpKey(AppSettings settings, String contents) async {
    late final String normalized;
    try {
      normalized = validateAndNormalizePrivateKey(contents);
    } on AppException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
      return;
    }
    await ref
        .read(secureStorageServiceProvider)
        .writeSftpPrivateKey(normalized);
    final next = _buildSettingsFromFields(
      settings.copyWith(
        sftpProfile: settings.sftpProfile.copyWith(hasImportedKey: true),
      ),
    );
    ref.read(settingsControllerProvider.notifier).save(next);
    await _persistSftpPassphrase(next);
    await _refreshSftpSecretState(next);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Restricted SFTP key saved')),
      );
    }
  }

  Future<void> _removeSshKey(AppSettings settings) async {
    final storage = ref.read(secureStorageServiceProvider);
    await storage.clearSshPrivateKey();
    await storage.clearSshPassphrase();
    _sshPassphrase.clear();
    final next = _buildSettingsFromFields(
      settings.copyWith(
        sshProfile: settings.sshProfile.copyWith(hasImportedKey: false),
      ),
    );
    ref.read(settingsControllerProvider.notifier).save(next);
    await _refreshSshSecretState(next);
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('SSH private key removed')));
    }
  }

  Future<void> _removeSftpKey(AppSettings settings) async {
    final storage = ref.read(secureStorageServiceProvider);
    await storage.clearSftpPrivateKey();
    await storage.clearSftpPassphrase();
    _sftpPassphrase.clear();
    final next = _buildSettingsFromFields(
      settings.copyWith(
        sftpProfile: settings.sftpProfile.copyWith(hasImportedKey: false),
      ),
    );
    ref.read(settingsControllerProvider.notifier).save(next);
    await _refreshSftpSecretState(next);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Restricted SFTP key removed')),
      );
    }
  }

  Future<void> _resetTrustedFingerprint(ConnectionProfile profile) async {
    await ref
        .read(sshConnectionServiceProvider)
        .resetTrustedFingerprint(profile);
    await _refreshSshSecretState(ref.read(settingsControllerProvider));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Trusted fingerprint reset')),
      );
    }
  }

  Future<void> _resetSftpTrustedFingerprint(ConnectionProfile profile) async {
    await ref
        .read(sftpConnectionServiceProvider)
        .resetTrustedFingerprint(profile);
    await _refreshSftpSecretState(ref.read(settingsControllerProvider));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Trusted fingerprint reset')),
      );
    }
  }

  Future<void> _refreshSshSecretState(AppSettings settings) async {
    final storage = ref.read(secureStorageServiceProvider);
    final service = ref.read(sshConnectionServiceProvider);
    final key = await storage.readSshPrivateKey();
    final passphrase = await storage.readSshPassphrase();
    final fingerprint = await service.readTrustedFingerprint(
      settings.sshProfile,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _sshKeySummary = key == null || key.isEmpty ? null : _summarizeKey(key);
      _sshTrustedFingerprint = fingerprint;
      _sshPassphraseRemembered = passphrase != null && passphrase.isNotEmpty;
    });
  }

  Future<void> _refreshSftpSecretState(AppSettings settings) async {
    final storage = ref.read(secureStorageServiceProvider);
    final service = ref.read(sftpConnectionServiceProvider);
    final key = await storage.readSftpPrivateKey();
    final passphrase = await storage.readSftpPassphrase();
    final fingerprint = await service.readTrustedFingerprint(
      settings.sftpProfile,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _sftpKeySummary = key == null || key.isEmpty ? null : _summarizeKey(key);
      _sftpTrustedFingerprint = fingerprint;
      _sftpPassphraseRemembered = passphrase != null && passphrase.isNotEmpty;
    });
  }

  String _summarizeKey(String key) {
    final header = key
        .split('\n')
        .firstWhere(
          (line) => line.startsWith('-----BEGIN '),
          orElse: () => 'Imported key',
        )
        .replaceAll('-----BEGIN ', '')
        .replaceAll('-----', '')
        .trim();
    return '$header (${key.length} chars)';
  }

  String _describeError(Object error) {
    if (error is AppException) {
      return error.message;
    }
    return error.toString();
  }
}
