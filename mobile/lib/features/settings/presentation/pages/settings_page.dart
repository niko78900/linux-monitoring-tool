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
import '../../../../core/widgets/section_card.dart';
import '../../../dashboard/data/monitoring_api_client.dart';
import '../../../files/data/sftp_connection_service.dart';
import '../../../network/data/control_api_client.dart';
import '../../../mobile_alerts/data/mobile_alert_service.dart';
import '../../../mobile_alerts/domain/models/mobile_alert_models.dart';
import '../../../server_widget/data/server_widget_catalog.dart';
import '../../../server_widget/data/server_widget_service.dart';
import '../../../terminal/data/ssh_connection_service.dart';
import '../../../terminal/presentation/widgets/terminal_connection_dialogs.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final _monitoringUrl = TextEditingController();
  final _controlUrl = TextEditingController();
  final _controlToken = TextEditingController();
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
  final _widgetSecondaryMountpoint = TextEditingController();
  bool _loaded = false;
  bool _testingSsh = false;
  bool _testingSftp = false;
  bool _mobileAlertBusy = false;
  String? _requestingWidgetPinProvider;
  MobileAlertStatus? _mobileAlertStatus;
  MobileNotificationPermissionState? _notificationPermission;
  String? _mobileAlertStatusText;
  String? _sshKeySummary;
  String? _sshTrustedFingerprint;
  String? _sftpKeySummary;
  String? _sftpTrustedFingerprint;

  @override
  void dispose() {
    _monitoringUrl.dispose();
    _controlUrl.dispose();
    _controlToken.dispose();
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
    _widgetSecondaryMountpoint.dispose();
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
        SectionCard(
          title: 'Monitoring',
          child: Column(
            children: [
              TextField(
                controller: _monitoringUrl,
                decoration: const InputDecoration(
                  labelText: 'Monitoring API URL',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              _PollingField(
                label: 'Summary polling ms',
                value: settings.summaryPollingMs,
                onChanged: (value) =>
                    _save(settings.copyWith(summaryPollingMs: value)),
              ),
              _PollingField(
                label: 'Details polling ms',
                value: settings.detailsPollingMs,
                onChanged: (value) =>
                    _save(settings.copyWith(detailsPollingMs: value)),
              ),
              _PollingField(
                label: 'Health polling ms',
                value: settings.healthPollingMs,
                onChanged: (value) =>
                    _save(settings.copyWith(healthPollingMs: value)),
              ),
              _PollingField(
                label: 'Docker polling ms',
                value: settings.dockerPollingMs,
                onChanged: (value) =>
                    _save(settings.copyWith(dockerPollingMs: value)),
              ),
              Row(
                children: [
                  FilledButton(
                    onPressed: () => _save(
                      settings.copyWith(monitoringApiUrl: _monitoringUrl.text),
                    ),
                    child: const Text('Save monitoring'),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  OutlinedButton(
                    onPressed: _testMonitoring,
                    child: const Text('Test monitoring API'),
                  ),
                ],
              ),
            ],
          ),
        ),
        SectionCard(
          title: 'Control Agent',
          child: Column(
            children: [
              TextField(
                controller: _controlUrl,
                decoration: const InputDecoration(labelText: 'Control API URL'),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _controlToken,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Control API token',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  FilledButton(
                    onPressed: () => _saveControl(settings),
                    child: const Text('Save control'),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  OutlinedButton(
                    onPressed: _testControl,
                    child: const Text('Test control API'),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  TextButton(
                    onPressed: _clearToken,
                    child: const Text('Clear token'),
                  ),
                ],
              ),
            ],
          ),
        ),
        SectionCard(
          title: 'Terminal',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _sshName,
                decoration: const InputDecoration(
                  labelText: 'SSH profile name',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _sshHost,
                decoration: const InputDecoration(labelText: 'SSH host'),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _sshPort,
                decoration: const InputDecoration(labelText: 'SSH port'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _sshUser,
                decoration: const InputDecoration(labelText: 'SSH username'),
              ),
              const SizedBox(height: AppSpacing.md),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: settings.sshProfile.storePassphrase,
                onChanged: (value) => _setSshPassphraseStorage(settings, value),
                title: const Text('Store passphrase in secure storage'),
              ),
              if (settings.sshProfile.storePassphrase) ...[
                TextField(
                  controller: _sshPassphrase,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'SSH key passphrase',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              _InfoLine(
                label: 'Imported key',
                value: _sshKeySummary ?? 'No key imported',
              ),
              const SizedBox(height: AppSpacing.sm),
              _InfoLine(
                label: 'Trusted host fingerprint',
                value:
                    _sshTrustedFingerprint ?? 'No trusted fingerprint stored',
                selectable: true,
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  FilledButton(
                    onPressed: () => _saveProfiles(settings),
                    child: const Text('Save terminal'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _importSshKey(settings),
                    icon: const Icon(Icons.upload_file),
                    label: Text(
                      settings.sshProfile.hasImportedKey
                          ? 'Replace key'
                          : 'Import private key',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _pasteSshKey(settings),
                    icon: const Icon(Icons.content_paste),
                    label: const Text('Paste private key'),
                  ),
                  TextButton(
                    onPressed: settings.sshProfile.hasImportedKey
                        ? () => _removeSshKey(settings)
                        : null,
                    child: const Text('Remove key'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  OutlinedButton(
                    onPressed: _testingSsh ? null : () => _testSsh(settings),
                    child: Text(
                      _testingSsh ? 'Testing...' : 'Test SSH connection',
                    ),
                  ),
                  TextButton(
                    onPressed: _sshTrustedFingerprint == null
                        ? null
                        : () => _resetTrustedFingerprint(settings.sshProfile),
                    child: const Text('Reset trusted fingerprint'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: settings.allowSftpUpload,
                onChanged: (value) =>
                    _save(settings.copyWith(allowSftpUpload: value)),
                title: const Text('Allow uploads'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: settings.allowSftpCreateDirectory,
                onChanged: (value) =>
                    _save(settings.copyWith(allowSftpCreateDirectory: value)),
                title: const Text('Allow create directory'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: settings.allowSftpRename,
                onChanged: (value) =>
                    _save(settings.copyWith(allowSftpRename: value)),
                title: const Text('Allow rename'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: settings.allowSftpMove,
                onChanged: (value) =>
                    _save(settings.copyWith(allowSftpMove: value)),
                title: const Text('Allow move'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: settings.allowSftpSoftDelete,
                onChanged: (value) =>
                    _save(settings.copyWith(allowSftpSoftDelete: value)),
                title: const Text('Allow soft delete'),
              ),
            ],
          ),
        ),
        SectionCard(
          title: 'Files',
          child: Column(
            children: [
              TextField(
                controller: _sftpName,
                decoration: const InputDecoration(
                  labelText: 'SFTP profile name',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _sftpHost,
                decoration: const InputDecoration(labelText: 'SFTP host'),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _sftpPort,
                decoration: const InputDecoration(labelText: 'SFTP port'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _sftpUser,
                decoration: const InputDecoration(labelText: 'SFTP username'),
              ),
              const SizedBox(height: AppSpacing.md),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: settings.sftpProfile.storePassphrase,
                onChanged: (value) =>
                    _setSftpPassphraseStorage(settings, value),
                title: const Text('Store passphrase in secure storage'),
              ),
              if (settings.sftpProfile.storePassphrase) ...[
                TextField(
                  controller: _sftpPassphrase,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'SFTP key passphrase',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              TextField(
                controller: _sftpRoot,
                decoration: const InputDecoration(
                  labelText: 'Configured virtual root',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              _InfoLine(
                label: 'Imported key',
                value: _sftpKeySummary ?? 'No key imported',
              ),
              const SizedBox(height: AppSpacing.sm),
              _InfoLine(
                label: 'Trusted host fingerprint',
                value:
                    _sftpTrustedFingerprint ?? 'No trusted fingerprint stored',
                selectable: true,
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  FilledButton(
                    onPressed: () => _saveProfiles(settings),
                    child: const Text('Save files'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _importSftpKey(settings),
                    icon: const Icon(Icons.upload_file),
                    label: Text(
                      settings.sftpProfile.hasImportedKey
                          ? 'Replace key'
                          : 'Import restricted key',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _pasteSftpKey(settings),
                    icon: const Icon(Icons.content_paste),
                    label: const Text('Paste restricted key'),
                  ),
                  TextButton(
                    onPressed: settings.sftpProfile.hasImportedKey
                        ? () => _removeSftpKey(settings)
                        : null,
                    child: const Text('Remove key'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  OutlinedButton(
                    onPressed: _testingSftp ? null : () => _testSftp(settings),
                    child: Text(
                      _testingSftp ? 'Testing...' : 'Test SFTP connection',
                    ),
                  ),
                  TextButton(
                    onPressed: _sftpTrustedFingerprint == null
                        ? null
                        : () => _resetSftpTrustedFingerprint(
                            settings.sftpProfile,
                          ),
                    child: const Text('Reset trusted fingerprint'),
                  ),
                ],
              ),
            ],
          ),
        ),
        SectionCard(
          title: 'Widgets & Alerts',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Home-screen widgets',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _widgetMountpoint,
                decoration: const InputDecoration(
                  labelText: 'Primary storage mountpoint',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _widgetSecondaryMountpoint,
                decoration: const InputDecoration(
                  labelText: 'Secondary storage mountpoint',
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: settings.widgetShowSecondaryStorage,
                onChanged: (value) =>
                    _save(settings.copyWith(widgetShowSecondaryStorage: value)),
                title: const Text('Show secondary storage row'),
              ),
              DropdownButtonFormField<int>(
                initialValue: settings.widgetBackgroundRefreshMinutes,
                decoration: const InputDecoration(
                  labelText: 'Background refresh interval',
                ),
                items: const [
                  DropdownMenuItem(value: 15, child: Text('15 minutes')),
                  DropdownMenuItem(value: 30, child: Text('30 minutes')),
                  DropdownMenuItem(value: 60, child: Text('60 minutes')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    _save(
                      settings.copyWith(widgetBackgroundRefreshMinutes: value),
                    );
                  }
                },
              ),
              const SizedBox(height: AppSpacing.md),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: settings.widgetShowNetworkThroughput,
                onChanged: (value) => _save(
                  settings.copyWith(widgetShowNetworkThroughput: value),
                ),
                title: const Text('Show network throughput row'),
              ),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  FilledButton(
                    onPressed: () => _save(
                      settings.copyWith(
                        widgetStorageMountpoint: _widgetMountpoint.text,
                        widgetSecondaryStorageMountpoint:
                            _widgetSecondaryMountpoint.text,
                      ),
                    ),
                    child: const Text('Save widget settings'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _refreshWidgetSnapshots,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refresh widget data now'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 900 ? 2 : 1;
                  return GridView.count(
                    crossAxisCount: columns,
                    crossAxisSpacing: AppSpacing.md,
                    mainAxisSpacing: AppSpacing.md,
                    childAspectRatio: columns == 1 ? 4.2 : 3.2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      for (final widget in homeScreenWidgets)
                        _WidgetCatalogCard(
                          widget: widget,
                          requesting:
                              _requestingWidgetPinProvider ==
                              widget.providerName,
                          onAdd: () => _requestPinWidget(widget.providerName),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: AppSpacing.lg),
              const Divider(),
              const SizedBox(height: AppSpacing.md),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Push notifications',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: settings.mobilePushAlertsEnabled,
                onChanged: _mobileAlertBusy
                    ? null
                    : (value) => value
                          ? _enablePushAlerts(settings)
                          : _disablePushAlerts(settings),
                title: const Text('Enable push alerts'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: settings.mobilePushIncludeRecovery,
                onChanged: (value) =>
                    _save(settings.copyWith(mobilePushIncludeRecovery: value)),
                title: const Text('Include recovery notifications'),
              ),
              _InfoLine(
                label: 'Permission',
                value: _notificationPermission?.label ?? 'Not checked',
              ),
              const SizedBox(height: AppSpacing.sm),
              _InfoLine(label: 'Registration', value: _registrationLabel()),
              const SizedBox(height: AppSpacing.sm),
              _InfoLine(
                label: 'Channel',
                value: 'Configured after Firebase initializes',
              ),
              if (_mobileAlertStatusText != null) ...[
                const SizedBox(height: AppSpacing.sm),
                _InfoLine(label: 'Last action', value: _mobileAlertStatusText!),
              ],
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  OutlinedButton.icon(
                    onPressed: _mobileAlertBusy
                        ? null
                        : () => _refreshMobileAlertStatus(settings),
                    icon: const Icon(Icons.sync),
                    label: const Text('Refresh push status'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _mobileAlertBusy
                        ? null
                        : () => _enablePushAlerts(settings),
                    icon: const Icon(Icons.app_registration),
                    label: const Text('Re-register this tablet'),
                  ),
                  FilledButton.icon(
                    onPressed: _mobileAlertBusy
                        ? null
                        : () => _sendTestPush(settings),
                    icon: const Icon(Icons.notifications_active),
                    label: const Text('Send test notification'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => unawaited(
                      MobileAlertService.instance
                          .openAndroidNotificationSettings(),
                    ),
                    icon: const Icon(Icons.settings),
                    label: const Text('Android notification settings'),
                  ),
                ],
              ),
            ],
          ),
        ),
        SectionCard(
          title: 'Tablet',
          child: Column(
            children: [
              SwitchListTile(
                value: settings.keepScreenAwakeOnOverview,
                onChanged: (value) =>
                    _save(settings.copyWith(keepScreenAwakeOnOverview: value)),
                title: const Text('Keep screen awake on Overview'),
              ),
              SwitchListTile(
                value: settings.requirePrivilegedUnlock,
                onChanged: (value) =>
                    _save(settings.copyWith(requirePrivilegedUnlock: value)),
                title: const Text('Privileged-tab lock'),
              ),
              DropdownButtonFormField<PrivilegedUnlockTimeout>(
                initialValue: settings.unlockTimeout,
                decoration: const InputDecoration(labelText: 'Unlock timeout'),
                items: [
                  for (final option in PrivilegedUnlockTimeout.values)
                    DropdownMenuItem(value: option, child: Text(option.label)),
                ],
                onChanged: (value) {
                  if (value != null) {
                    _save(settings.copyWith(unlockTimeout: value));
                  }
                },
              ),
              const SizedBox(height: AppSpacing.md),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () =>
                      ref.read(appLockControllerProvider.notifier).lock(),
                  icon: const Icon(Icons.lock),
                  label: const Text('Manually lock now'),
                ),
              ),
            ],
          ),
        ),
        SectionCard(
          title: 'Debug',
          child: Column(
            children: [
              SwitchListTile(
                value: settings.showRawApiErrors,
                onChanged: (value) =>
                    _save(settings.copyWith(showRawApiErrors: value)),
                title: const Text('Show raw API errors'),
              ),
              SwitchListTile(
                value: settings.showRequestTiming,
                onChanged: (value) =>
                    _save(settings.copyWith(showRequestTiming: value)),
                title: const Text('Show request timing'),
              ),
              TextButton(
                onPressed: () => ref
                    .read(settingsControllerProvider.notifier)
                    .resetOnboarding(),
                child: const Text('Run onboarding again'),
              ),
            ],
          ),
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
    _widgetSecondaryMountpoint.text = settings.widgetSecondaryStorageMountpoint;
    final storage = ref.read(secureStorageServiceProvider);
    storage.readControlToken().then((value) {
      if (mounted && value != null && _controlToken.text.isEmpty) {
        _controlToken.text = value;
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
    if (settings.sshProfile.storePassphrase &&
        _sshPassphrase.text.trim().isNotEmpty) {
      await storage.writeSshPassphrase(_sshPassphrase.text);
    } else {
      await storage.clearSshPassphrase();
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
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Settings saved')));
    }
  }

  Future<void> _persistSftpPassphrase(AppSettings settings) async {
    final storage = ref.read(secureStorageServiceProvider);
    if (settings.sftpProfile.storePassphrase &&
        _sftpPassphrase.text.trim().isNotEmpty) {
      await storage.writeSftpPassphrase(_sftpPassphrase.text);
    } else {
      await storage.clearSftpPassphrase();
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
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Settings saved')));
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
          .readControlToken();
      final permission = await MobileAlertService.instance.permissionState();
      MobileAlertStatus? status;
      try {
        status = await MobileAlertService.instance.status(
          settings: settings,
          preferences: preferences,
          controlToken: token,
        );
      } catch (_) {
        status = null;
      }
      if (mounted) {
        setState(() {
          _notificationPermission = permission;
          _mobileAlertStatus = status;
          _mobileAlertStatusText = status == null
              ? 'Control-agent push status unavailable'
              : 'Push status refreshed';
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
          .readControlToken();
      final permission = await MobileAlertService.instance.requestPermission();
      final status = await MobileAlertService.instance.register(
        settings: settings,
        preferences: preferences,
        controlToken: token,
      );
      final next = settings.copyWith(mobilePushAlertsEnabled: true);
      ref.read(settingsControllerProvider.notifier).save(next);
      if (mounted) {
        setState(() {
          _notificationPermission = permission;
          _mobileAlertStatus = status;
          _mobileAlertStatusText = 'Push alerts enabled';
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
          .readControlToken();
      final status = await MobileAlertService.instance.disable(
        settings: settings,
        preferences: preferences,
        controlToken: token,
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
          .readControlToken();
      final permission = await MobileAlertService.instance.requestPermission();
      final result = await MobileAlertService.instance.sendRoundTripTest(
        settings: settings,
        preferences: preferences,
        controlToken: token,
      );
      final status = await MobileAlertService.instance.status(
        settings: settings,
        preferences: preferences,
        controlToken: token,
      );
      if (mounted) {
        setState(() {
          _notificationPermission = permission;
          _mobileAlertStatus = status;
          _mobileAlertStatusText =
              'Test notification requested (${result.sentCount} sent)';
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
            onPassphraseRequired: () => showPassphrasePromptDialog(
              context,
              title: 'Enter the SSH key passphrase',
            ),
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
            onPassphraseRequired: () => showPassphrasePromptDialog(
              context,
              title: 'Enter the SFTP key passphrase',
            ),
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

  Future<void> _importSshKey(AppSettings settings) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pem', 'key', 'txt'],
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
    final normalized = contents.trim();
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
      type: FileType.custom,
      allowedExtensions: const ['pem', 'key', 'txt'],
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
    final normalized = contents.trim();
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
    final fingerprint = await service.readTrustedFingerprint(
      settings.sshProfile,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _sshKeySummary = key == null || key.isEmpty ? null : _summarizeKey(key);
      _sshTrustedFingerprint = fingerprint;
    });
  }

  Future<void> _refreshSftpSecretState(AppSettings settings) async {
    final storage = ref.read(secureStorageServiceProvider);
    final service = ref.read(sftpConnectionServiceProvider);
    final key = await storage.readSftpPrivateKey();
    final fingerprint = await service.readTrustedFingerprint(
      settings.sftpProfile,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _sftpKeySummary = key == null || key.isEmpty ? null : _summarizeKey(key);
      _sftpTrustedFingerprint = fingerprint;
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

class _PollingField extends StatelessWidget {
  const _PollingField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: DropdownButtonFormField<int>(
        initialValue: value,
        decoration: InputDecoration(labelText: label),
        items: const [
          DropdownMenuItem(value: 1000, child: Text('1 second')),
          DropdownMenuItem(value: 3000, child: Text('3 seconds')),
          DropdownMenuItem(value: 5000, child: Text('5 seconds')),
          DropdownMenuItem(value: 10000, child: Text('10 seconds')),
          DropdownMenuItem(value: 15000, child: Text('15 seconds')),
          DropdownMenuItem(value: 30000, child: Text('30 seconds')),
          DropdownMenuItem(value: 60000, child: Text('1 minute')),
        ],
        onChanged: (next) {
          if (next != null) {
            onChanged(next);
          }
        },
      ),
    );
  }
}

class _WidgetCatalogCard extends StatelessWidget {
  const _WidgetCatalogCard({
    required this.widget,
    required this.requesting,
    required this.onAdd,
  });

  final HomeScreenWidgetDescriptor widget;
  final bool requesting;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            const Icon(Icons.widgets),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    widget.displayName,
                    style: Theme.of(context).textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '${widget.recommendedSize} | ${widget.purpose}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: requesting ? null : onAdd,
              icon: const Icon(Icons.add),
              label: Text(requesting ? 'Adding...' : 'Add'),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({
    required this.label,
    required this.value,
    this.selectable = false,
  });

  final String label;
  final String value;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 180,
          child: Text(
            label,
            style: style?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          child: selectable ? SelectableText(value) : Text(value, style: style),
        ),
      ],
    );
  }
}
