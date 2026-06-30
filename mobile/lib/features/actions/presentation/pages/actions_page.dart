import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/config/app_settings.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/errors/error_mapper.dart';
import '../../../../core/security/secure_storage_service.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/section_card.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../../core/widgets/status_tone.dart';
import '../utils/benchmark_error_mapper.dart';
import '../utils/benchmark_ui_state.dart';
import '../widgets/benchmark_controls.dart';
import '../widgets/benchmark_settings_dialog.dart';
import '../../domain/models/benchmark_models.dart';
import '../../../network/data/control_api_client.dart';
import '../../../network/domain/models/device_models.dart';
import '../../../network/presentation/providers/control_providers.dart';

class ActionsPage extends ConsumerStatefulWidget {
  const ActionsPage({super.key});

  @override
  ConsumerState<ActionsPage> createState() => _ActionsPageState();
}

class _ActionsPageState extends ConsumerState<ActionsPage> {
  bool _loadingToken = true;
  bool _testing = false;
  bool _waking = false;
  bool _benchmarkBusy = false;
  String? _token;
  String? _statusMessage;
  BenchmarkNotice? _benchmarkNotice;
  _ControlStatus _status = _ControlStatus.disconnected;
  BenchmarkStatus? _benchmarkStatus;
  Timer? _benchmarkPollTimer;
  final _dateFormat = DateFormat.yMd().add_Hms();

  @override
  void initState() {
    super.initState();
    _loadToken();
  }

  @override
  void dispose() {
    _benchmarkPollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsControllerProvider);
    final controlUrl = settings.controlApiUrl.trim();
    if (controlUrl.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: EmptyState(
          icon: Icons.power_settings_new,
          title: 'Configure the control agent first',
          message:
              'Set the Control API URL in Settings before using Wake Main PC.',
          action: FilledButton(
            onPressed: () => context.go('/settings'),
            child: const Text('Open Settings'),
          ),
        ),
      );
    }

    if (_loadingToken) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_token == null || _token!.trim().isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: EmptyState(
          icon: Icons.key,
          title: 'Control token required',
          message:
              'Store the Control API bearer token in Settings before sending privileged actions.',
          action: FilledButton(
            onPressed: () => context.go('/settings'),
            child: const Text('Open Settings'),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        _MainPcQuickActions(
          testing: _testing,
          waking: _waking,
          onTestControl: () => _testControl(settings),
          onWake: () => _confirmWake(settings),
        ),
        const SizedBox(height: AppSpacing.lg),
        BenchmarkControls(
          status: _benchmarkStatus,
          notice: _benchmarkNotice,
          busy: _benchmarkBusy,
          dateFormat: _dateFormat,
          onCpuSelected: (kind) => _startCpuBenchmark(settings, kind),
          onGpuSelected: () => _startGpuBenchmark(settings),
          onStop: () => _stopBenchmark(settings),
          onRefresh: () => _refreshBenchmarkStatus(settings),
        ),
        const SizedBox(height: AppSpacing.lg),
        SectionCard(
          title: 'Control Agent',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  StatusBadge(label: _status.label, tone: _status.tone),
                  if (_statusMessage != null) Text(_statusMessage!),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              const Text('Privileged requests are fixed server-side.'),
              const SizedBox(height: AppSpacing.lg),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  OutlinedButton.icon(
                    onPressed: _testing ? null : () => _testControl(settings),
                    icon: const Icon(Icons.network_check),
                    label: Text(_testing ? 'Testing...' : 'Test control agent'),
                  ),
                  FilledButton.icon(
                    onPressed: _waking ? null : () => _confirmWake(settings),
                    icon: const Icon(Icons.power_settings_new),
                    label: Text(_waking ? 'Sending...' : 'Wake Main PC'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _loadToken() async {
    final token = await ref
        .read(secureStorageServiceProvider)
        .readControlToken();
    if (!mounted) {
      return;
    }
    setState(() {
      _token = token;
      _loadingToken = false;
    });
  }

  Future<void> _testControl(AppSettings settings) async {
    setState(() {
      _testing = true;
      _statusMessage = null;
    });
    try {
      final client = ControlApiClient(
        baseUrl: settings.controlApiUrl,
        token: _token,
      );
      final health = await client.getHealth();
      if (!mounted) {
        return;
      }
      setState(() {
        _status = _ControlStatus.connected;
        _statusMessage = 'Connected to ${health.appName} ${health.version}';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = _ControlStatus.error;
        _statusMessage = _describeError(error);
      });
    } finally {
      if (mounted) {
        setState(() => _testing = false);
      }
    }
  }

  Future<void> _confirmWake(AppSettings settings) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Wake Main PC?'),
          content: const Text(
            'Send the allowlisted Wake-on-LAN action through the control agent.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Wake'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }
    await _wakeMainPc(settings);
  }

  Future<void> _wakeMainPc(AppSettings settings) async {
    setState(() {
      _waking = true;
      _statusMessage = null;
    });
    try {
      final client = ControlApiClient(
        baseUrl: settings.controlApiUrl,
        token: _token,
      );
      final response = await client.wakeMainPc();
      if (!mounted) {
        return;
      }
      setState(() {
        _status = _ControlStatus.connected;
        _statusMessage =
            'Wake accepted for ${response.target}. Rate limit: ${response.rateLimitSeconds}s.';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = _ControlStatus.error;
        _statusMessage = _describeError(error);
      });
    } finally {
      if (mounted) {
        setState(() => _waking = false);
      }
    }
  }

  Future<void> _refreshBenchmarkStatus(
    AppSettings settings, {
    bool silent = false,
  }) async {
    if (!silent) {
      setState(() {
        _benchmarkBusy = true;
        _benchmarkNotice = null;
      });
    }
    try {
      final status = await _controlClient(settings).getBenchmarkStatus();
      if (!mounted) {
        return;
      }
      setState(() {
        _benchmarkStatus = status;
        _benchmarkNotice = benchmarkNoticeForStatus(status);
      });
      _syncBenchmarkPolling(status);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _benchmarkNotice = mapBenchmarkError(error));
      _benchmarkPollTimer?.cancel();
    } finally {
      if (mounted && !silent) {
        setState(() => _benchmarkBusy = false);
      }
    }
  }

  Future<BenchmarkStatus?> _ensureBenchmarkStatus(AppSettings settings) async {
    if (_benchmarkStatus != null) {
      return _benchmarkStatus;
    }
    try {
      final status = await _controlClient(settings).getBenchmarkStatus();
      if (mounted) {
        setState(() {
          _benchmarkStatus = status;
          _benchmarkNotice = benchmarkNoticeForStatus(status);
        });
        _syncBenchmarkPolling(status);
      }
      return status;
    } catch (error) {
      if (mounted) {
        setState(() => _benchmarkNotice = mapBenchmarkError(error));
      }
      return _benchmarkStatus;
    }
  }

  Future<void> _startCpuBenchmark(
    AppSettings settings,
    BenchmarkKind kind,
  ) async {
    final status = await _ensureBenchmarkStatus(settings);
    final nproc = status?.nproc ?? 1;
    final request = switch (kind) {
      BenchmarkKind.cpuSingle => await _promptBenchmarkSettings(
        title: 'Single-Core Benchmark',
        durationLabel: 'Duration seconds',
        durationDefault: 30,
        durationMin: 5,
        durationMax: 300,
      ),
      BenchmarkKind.cpuMulti => await _promptBenchmarkSettings(
        title: 'Multi-Core Benchmark',
        durationLabel: 'Duration seconds',
        durationDefault: 30,
        durationMin: 5,
        durationMax: 300,
        secondaryLabel: 'Threads',
        secondaryDefault: nproc,
        secondaryMin: 1,
        secondaryMax: nproc,
      ),
      BenchmarkKind.cpuStress => await _promptBenchmarkSettings(
        title: 'CPU Stress Test',
        durationLabel: 'Duration seconds',
        durationDefault: 60,
        durationMin: 10,
        durationMax: 300,
        secondaryLabel: 'Workers',
        secondaryDefault: nproc,
        secondaryMin: 1,
        secondaryMax: nproc,
      ),
      BenchmarkKind.gpuVkmark => null,
    };
    if (request == null) {
      return;
    }
    if (kind == BenchmarkKind.cpuStress) {
      final confirmed = await _confirmBenchmarkWarning(
        title: 'Start CPU stress test?',
        message: 'This intentionally loads the CPU and may raise temperatures.',
        confirmLabel: 'Start stress test',
      );
      if (confirmed != true) {
        return;
      }
    }
    await _startBenchmark(
      settings,
      BenchmarkStartRequest(
        kind: kind,
        durationSeconds: request.durationSeconds,
        threads: kind == BenchmarkKind.cpuMulti ? request.secondaryValue : null,
        workers: kind == BenchmarkKind.cpuStress
            ? request.secondaryValue
            : null,
      ),
    );
  }

  Future<void> _startGpuBenchmark(AppSettings settings) async {
    final confirmed = await _confirmBenchmarkWarning(
      title: 'Start GPU Vulkan benchmark?',
      message:
          'This runs a Vulkan GPU benchmark and may briefly increase GPU load.',
      confirmLabel: 'Start GPU test',
    );
    if (confirmed != true) {
      return;
    }
    await _startBenchmark(
      settings,
      const BenchmarkStartRequest(kind: BenchmarkKind.gpuVkmark),
    );
  }

  Future<void> _startBenchmark(
    AppSettings settings,
    BenchmarkStartRequest request,
  ) async {
    setState(() {
      _benchmarkBusy = true;
      _benchmarkNotice = null;
    });
    try {
      final status = await _controlClient(settings).startBenchmark(request);
      if (!mounted) {
        return;
      }
      setState(() {
        _benchmarkStatus = status;
        _benchmarkNotice = benchmarkNoticeForStatus(
          status,
          startedLabel: status.label ?? request.kind.label,
        );
      });
      _syncBenchmarkPolling(status);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _benchmarkNotice = mapBenchmarkError(error));
    } finally {
      if (mounted) {
        setState(() => _benchmarkBusy = false);
      }
    }
  }

  Future<void> _stopBenchmark(AppSettings settings) async {
    setState(() {
      _benchmarkBusy = true;
      _benchmarkNotice = null;
    });
    try {
      final status = await _controlClient(settings).stopBenchmark();
      if (!mounted) {
        return;
      }
      setState(() {
        _benchmarkStatus = status;
        _benchmarkNotice = benchmarkNoticeForStatus(
          status,
          fallbackMessage: 'Stop requested.',
        );
      });
      _syncBenchmarkPolling(status);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _benchmarkNotice = mapBenchmarkError(error));
    } finally {
      if (mounted) {
        setState(() => _benchmarkBusy = false);
      }
    }
  }

  Future<BenchmarkSettingsResult?> _promptBenchmarkSettings({
    required String title,
    required String durationLabel,
    required int durationDefault,
    required int durationMin,
    required int durationMax,
    String? secondaryLabel,
    int? secondaryDefault,
    int? secondaryMin,
    int? secondaryMax,
  }) {
    return showDialog<BenchmarkSettingsResult>(
      context: context,
      builder: (context) {
        return BenchmarkSettingsDialog(
          title: title,
          durationLabel: durationLabel,
          durationDefault: durationDefault,
          durationMin: durationMin,
          durationMax: durationMax,
          secondaryLabel: secondaryLabel,
          secondaryDefault: secondaryDefault,
          secondaryMin: secondaryMin,
          secondaryMax: secondaryMax,
        );
      },
    );
  }

  Future<bool?> _confirmBenchmarkWarning({
    required String title,
    required String message,
    required String confirmLabel,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    );
  }

  void _syncBenchmarkPolling(BenchmarkStatus status) {
    if (status.isRunning) {
      _benchmarkPollTimer ??= Timer.periodic(
        const Duration(seconds: 2),
        (_) => _refreshBenchmarkStatus(
          ref.read(settingsControllerProvider),
          silent: true,
        ),
      );
    } else {
      _benchmarkPollTimer?.cancel();
      _benchmarkPollTimer = null;
    }
  }

  ControlApiClient _controlClient(AppSettings settings) {
    return ControlApiClient(baseUrl: settings.controlApiUrl, token: _token);
  }

  String _describeError(Object error) {
    if (error is AppException) {
      return error.message;
    }
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map<String, dynamic>) {
        final detail = data['detail'];
        if (detail != null) {
          return detail.toString();
        }
      }
    }
    return mapError(error);
  }
}

enum _ControlStatus {
  disconnected('Not tested', StatusTone.unknown),
  connected('Reachable', StatusTone.healthy),
  error('Blocked', StatusTone.critical);

  const _ControlStatus(this.label, this.tone);

  final String label;
  final StatusTone tone;
}

class _MainPcQuickActions extends ConsumerWidget {
  const _MainPcQuickActions({
    required this.testing,
    required this.waking,
    required this.onTestControl,
    required this.onWake,
  });

  final bool testing;
  final bool waking;
  final VoidCallback onTestControl;
  final VoidCallback onWake;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devicesState = ref.watch(devicesDashboardProvider);
    final mainPc = devicesState.maybeWhen(
      data: (dashboard) => _findMainPc(dashboard.devices),
      orElse: () => null,
    );
    final ip = mainPc?.preferredIp;
    return SectionCard(
      title: 'Main PC quick actions',
      trailing: StatusBadge(
        label: mainPc == null
            ? 'Unknown'
            : mainPc.online
            ? 'Online'
            : 'Offline',
        tone: mainPc == null
            ? StatusTone.unknown
            : mainPc.online
            ? StatusTone.healthy
            : StatusTone.offline,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(ip == null ? 'Main PC IP not configured.' : 'Target: $ip'),
          if (mainPc?.probeSummary case final summary?)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(summary),
            ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              FilledButton.icon(
                onPressed: waking ? null : onWake,
                icon: const Icon(Icons.power_settings_new),
                label: Text(waking ? 'Sending...' : 'Wake Main PC'),
              ),
              OutlinedButton.icon(
                onPressed: ip == null ? null : () => _openRdp(context, ip),
                icon: const Icon(Icons.desktop_windows),
                label: const Text('Open RDP'),
              ),
              OutlinedButton.icon(
                onPressed: () => context.go('/terminal'),
                icon: const Icon(Icons.terminal),
                label: const Text('SSH to Main PC'),
              ),
              OutlinedButton.icon(
                onPressed: ip == null ? null : () => _copyIp(context, ip),
                icon: const Icon(Icons.copy),
                label: const Text('Copy Main PC IP'),
              ),
              OutlinedButton.icon(
                onPressed: testing
                    ? null
                    : () {
                        ref.invalidate(devicesDashboardProvider);
                        onTestControl();
                      },
                icon: const Icon(Icons.network_check),
                label: Text(testing ? 'Checking...' : 'Check status'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  KnownDevice? _findMainPc(List<KnownDevice> devices) {
    for (final device in devices) {
      final id = device.id.toLowerCase();
      final name = device.name.toLowerCase();
      if (id == 'main-pc' || name == 'main pc') {
        return device;
      }
    }
    return null;
  }

  Future<void> _openRdp(BuildContext context, String host) async {
    final uri = Uri.parse('ms-rd:connect?full%20address=s:$host');
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No RDP app could open this host.')),
      );
    }
  }

  Future<void> _copyIp(BuildContext context, String ip) async {
    await Clipboard.setData(ClipboardData(text: ip));
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Main PC IP copied.')));
    }
  }
}
