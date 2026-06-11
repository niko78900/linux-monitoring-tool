import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/config/app_settings.dart';
import '../../../core/errors/error_mapper.dart';
import '../../../core/networking/dio_factory.dart';
import '../../../core/security/secure_storage_service.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../features/dashboard/data/monitoring_api_client.dart';
import '../../../features/network/data/control_api_client.dart';

class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final _monitoringUrl = TextEditingController();
  final _controlUrl = TextEditingController();
  final _controlToken = TextEditingController();
  final _sshName = TextEditingController();
  final _sshHost = TextEditingController();
  final _sshUser = TextEditingController();
  final _sshPort = TextEditingController(text: '22');
  final _sftpName = TextEditingController();
  final _sftpHost = TextEditingController();
  final _sftpUser = TextEditingController();
  final _sftpPort = TextEditingController(text: '22');
  var _step = 0;
  var _keepAwake = false;
  var _requireUnlock = true;
  var _unlockTimeout = PrivilegedUnlockTimeout.fiveMinutes;
  var _testingMonitoring = false;
  var _testingControl = false;
  String? _monitoringResult;
  String? _controlResult;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsControllerProvider);
    _monitoringUrl.text = settings.monitoringApiUrl;
    _controlUrl.text = settings.controlApiUrl;
    _sshName.text = settings.sshProfile.displayName;
    _sshHost.text = settings.sshProfile.host;
    _sshUser.text = settings.sshProfile.username;
    _sshPort.text = settings.sshProfile.port.toString();
    _sftpName.text = settings.sftpProfile.displayName;
    _sftpHost.text = settings.sftpProfile.host;
    _sftpUser.text = settings.sftpProfile.username;
    _sftpPort.text = settings.sftpProfile.port.toString();
    _keepAwake = settings.keepScreenAwakeOnOverview;
    _requireUnlock = settings.requirePrivilegedUnlock;
    _unlockTimeout = settings.unlockTimeout;
  }

  @override
  void dispose() {
    _monitoringUrl.dispose();
    _controlUrl.dispose();
    _controlToken.dispose();
    _sshName.dispose();
    _sshHost.dispose();
    _sshUser.dispose();
    _sshPort.dispose();
    _sftpName.dispose();
    _sftpHost.dispose();
    _sftpUser.dispose();
    _sftpPort.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.xl),
              children: [
                Text(
                  'Homelab Tablet',
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Configure private Tailscale endpoints and local security preferences.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: AppSpacing.lg),
                Stepper(
                  currentStep: _step,
                  onStepTapped: (value) => setState(() => _step = value),
                  controlsBuilder: (context, details) => Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.lg),
                    child: Wrap(
                      spacing: AppSpacing.sm,
                      children: [
                        if (_step < 4)
                          FilledButton(
                            onPressed: () => setState(() => _step += 1),
                            child: const Text('Continue'),
                          )
                        else
                          FilledButton.icon(
                            onPressed: _finish,
                            icon: const Icon(Icons.check),
                            label: const Text('Finish'),
                          ),
                        if (_step > 0)
                          TextButton(
                            onPressed: () => setState(() => _step -= 1),
                            child: const Text('Back'),
                          ),
                      ],
                    ),
                  ),
                  steps: [
                    Step(
                      title: const Text('Monitoring API'),
                      isActive: _step == 0,
                      content: _MonitoringStep(
                        controller: _monitoringUrl,
                        testing: _testingMonitoring,
                        result: _monitoringResult,
                        onTest: _testMonitoring,
                      ),
                    ),
                    Step(
                      title: const Text('Control API'),
                      isActive: _step == 1,
                      content: _ControlStep(
                        urlController: _controlUrl,
                        tokenController: _controlToken,
                        testing: _testingControl,
                        result: _controlResult,
                        onTest: _testControl,
                      ),
                    ),
                    Step(
                      title: const Text('SSH Terminal Profile'),
                      isActive: _step == 2,
                      content: _ProfileStep(
                        name: _sshName,
                        host: _sshHost,
                        user: _sshUser,
                        port: _sshPort,
                        note:
                            'Private-key import, host-key trust, and SSH testing are available in Settings after onboarding.',
                      ),
                    ),
                    Step(
                      title: const Text('SFTP File Profile'),
                      isActive: _step == 3,
                      content: _ProfileStep(
                        name: _sftpName,
                        host: _sftpHost,
                        user: _sftpUser,
                        port: _sftpPort,
                        note:
                            'Use a separate restricted SFTP account. Restricted key import and connection testing are available in Settings after onboarding.',
                      ),
                    ),
                    Step(
                      title: const Text('Tablet Preferences'),
                      isActive: _step == 4,
                      content: Column(
                        children: [
                          SwitchListTile(
                            value: _keepAwake,
                            onChanged: (value) =>
                                setState(() => _keepAwake = value),
                            title: const Text('Keep screen awake on Overview'),
                          ),
                          SwitchListTile(
                            value: _requireUnlock,
                            onChanged: (value) =>
                                setState(() => _requireUnlock = value),
                            title: const Text(
                              'Require unlock for privileged tabs',
                            ),
                          ),
                          DropdownButtonFormField<PrivilegedUnlockTimeout>(
                            initialValue: _unlockTimeout,
                            decoration: const InputDecoration(
                              labelText: 'Unlock timeout',
                            ),
                            items: [
                              for (final option
                                  in PrivilegedUnlockTimeout.values)
                                DropdownMenuItem(
                                  value: option,
                                  child: Text(option.label),
                                ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _unlockTimeout = value);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _testMonitoring() async {
    setState(() {
      _testingMonitoring = true;
      _monitoringResult = null;
    });
    try {
      final client = MonitoringApiClient(
        DioFactory.create(baseUrl: _monitoringUrl.text),
      );
      final health = await client.getHealth();
      setState(
        () => _monitoringResult =
            'Connected to ${health.appName} ${health.version}',
      );
    } catch (error) {
      setState(() => _monitoringResult = mapError(error));
    } finally {
      setState(() => _testingMonitoring = false);
    }
  }

  Future<void> _testControl() async {
    if (_controlUrl.text.trim().isEmpty) {
      setState(() => _controlResult = 'Skipped');
      return;
    }
    setState(() {
      _testingControl = true;
      _controlResult = null;
    });
    try {
      final client = ControlApiClient(
        baseUrl: _controlUrl.text,
        token: _controlToken.text,
      );
      await client.getHealth();
      setState(() => _controlResult = 'Control agent reachable');
    } catch (error) {
      setState(() => _controlResult = mapError(error));
    } finally {
      setState(() => _testingControl = false);
    }
  }

  Future<void> _finish() async {
    final current = ref.read(settingsControllerProvider);
    final next = current.copyWith(
      monitoringApiUrl: _monitoringUrl.text.trim().isEmpty
          ? AppConfig.defaultMonitoringApiUrl
          : _monitoringUrl.text,
      controlApiUrl: _controlUrl.text,
      keepScreenAwakeOnOverview: _keepAwake,
      requirePrivilegedUnlock: _requireUnlock,
      unlockTimeout: _unlockTimeout,
      sshProfile: current.sshProfile.copyWith(
        displayName: _sshName.text,
        host: _sshHost.text,
        username: _sshUser.text,
        port: int.tryParse(_sshPort.text) ?? 22,
      ),
      sftpProfile: current.sftpProfile.copyWith(
        displayName: _sftpName.text,
        host: _sftpHost.text,
        username: _sftpUser.text,
        port: int.tryParse(_sftpPort.text) ?? 22,
      ),
    );
    await ref
        .read(secureStorageServiceProvider)
        .writeControlToken(_controlToken.text);
    ref.read(settingsControllerProvider.notifier).completeOnboarding(next);
  }
}

class _MonitoringStep extends StatelessWidget {
  const _MonitoringStep({
    required this.controller,
    required this.testing,
    required this.result,
    required this.onTest,
  });

  final TextEditingController controller;
  final bool testing;
  final String? result;
  final VoidCallback onTest;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Monitoring API URL',
            hintText: 'https://server.tailnet.ts.net/monitor/api',
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: testing ? null : onTest,
              icon: const Icon(Icons.network_check),
              label: Text(testing ? 'Testing...' : 'Test connection'),
            ),
            const SizedBox(width: AppSpacing.md),
            if (result != null) Expanded(child: Text(result!)),
          ],
        ),
      ],
    );
  }
}

class _ControlStep extends StatelessWidget {
  const _ControlStep({
    required this.urlController,
    required this.tokenController,
    required this.testing,
    required this.result,
    required this.onTest,
  });

  final TextEditingController urlController;
  final TextEditingController tokenController;
  final bool testing;
  final String? result;
  final VoidCallback onTest;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: urlController,
          decoration: const InputDecoration(
            labelText: 'Control API URL',
            hintText: 'https://server.tailnet.ts.net/control/api',
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: tokenController,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Control API token'),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: testing ? null : onTest,
              icon: const Icon(Icons.network_check),
              label: Text(testing ? 'Testing...' : 'Test connection'),
            ),
            const SizedBox(width: AppSpacing.md),
            if (result != null) Expanded(child: Text(result!)),
          ],
        ),
      ],
    );
  }
}

class _ProfileStep extends StatelessWidget {
  const _ProfileStep({
    required this.name,
    required this.host,
    required this.user,
    required this.port,
    required this.note,
  });

  final TextEditingController name;
  final TextEditingController host;
  final TextEditingController user;
  final TextEditingController port;
  final String note;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: name,
          decoration: const InputDecoration(labelText: 'Display name'),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: host,
          decoration: const InputDecoration(labelText: 'Host'),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: port,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Port'),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: user,
          decoration: const InputDecoration(labelText: 'Username'),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(note),
      ],
    );
  }
}
