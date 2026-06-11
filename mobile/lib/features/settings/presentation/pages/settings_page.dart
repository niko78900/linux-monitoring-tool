import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/app_settings.dart';
import '../../../../core/security/app_lock_service.dart';
import '../../../../core/security/secure_storage_service.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/section_card.dart';
import '../../../dashboard/data/monitoring_api_client.dart';
import '../../../network/data/control_api_client.dart';
import '../../../../core/networking/dio_factory.dart';

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
  final _sftpName = TextEditingController();
  final _sftpHost = TextEditingController();
  final _sftpPort = TextEditingController();
  final _sftpUser = TextEditingController();
  final _sftpRoot = TextEditingController();
  bool _loaded = false;

  @override
  void dispose() {
    _monitoringUrl.dispose();
    _controlUrl.dispose();
    _controlToken.dispose();
    _sshName.dispose();
    _sshHost.dispose();
    _sshPort.dispose();
    _sshUser.dispose();
    _sftpName.dispose();
    _sftpHost.dispose();
    _sftpPort.dispose();
    _sftpUser.dispose();
    _sftpRoot.dispose();
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
              Row(
                children: [
                  FilledButton(
                    onPressed: () => _saveProfiles(settings),
                    child: const Text('Save terminal'),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  const Text('Key import and SSH test arrive in Phase 4.'),
                ],
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
              TextField(
                controller: _sftpRoot,
                decoration: const InputDecoration(
                  labelText: 'Configured virtual root',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  FilledButton(
                    onPressed: () => _saveProfiles(settings),
                    child: const Text('Save files'),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  const Text(
                    'Restricted SFTP connection test arrives in Phase 5.',
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
    ref.read(secureStorageServiceProvider).readControlToken().then((value) {
      if (mounted && value != null && _controlToken.text.isEmpty) {
        _controlToken.text = value;
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
    _save(
      settings.copyWith(
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
      ),
    );
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
