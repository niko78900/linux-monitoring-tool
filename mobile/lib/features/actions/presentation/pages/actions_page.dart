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
  String? _benchmarkMessage;
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
        _BenchmarkControls(
          status: _benchmarkStatus,
          message: _benchmarkMessage,
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
        _benchmarkMessage = null;
      });
    }
    try {
      final status = await _controlClient(settings).getBenchmarkStatus();
      if (!mounted) {
        return;
      }
      setState(() {
        _benchmarkStatus = status;
        _benchmarkMessage = status.detail;
      });
      _syncBenchmarkPolling(status);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _benchmarkMessage = _describeError(error));
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
          _benchmarkMessage = status.detail;
        });
        _syncBenchmarkPolling(status);
      }
      return status;
    } catch (error) {
      if (mounted) {
        setState(() => _benchmarkMessage = _describeError(error));
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
      _benchmarkMessage = null;
    });
    try {
      final status = await _controlClient(settings).startBenchmark(request);
      if (!mounted) {
        return;
      }
      setState(() {
        _benchmarkStatus = status;
        _benchmarkMessage = 'Started ${status.label ?? request.kind.label}.';
      });
      _syncBenchmarkPolling(status);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _benchmarkMessage = _describeError(error));
    } finally {
      if (mounted) {
        setState(() => _benchmarkBusy = false);
      }
    }
  }

  Future<void> _stopBenchmark(AppSettings settings) async {
    setState(() {
      _benchmarkBusy = true;
      _benchmarkMessage = null;
    });
    try {
      final status = await _controlClient(settings).stopBenchmark();
      if (!mounted) {
        return;
      }
      setState(() {
        _benchmarkStatus = status;
        _benchmarkMessage = status.detail ?? 'Stop requested.';
      });
      _syncBenchmarkPolling(status);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _benchmarkMessage = _describeError(error));
    } finally {
      if (mounted) {
        setState(() => _benchmarkBusy = false);
      }
    }
  }

  Future<_BenchmarkSettingsResult?> _promptBenchmarkSettings({
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
    return showDialog<_BenchmarkSettingsResult>(
      context: context,
      builder: (context) {
        return _BenchmarkSettingsDialog(
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

class _BenchmarkControls extends StatelessWidget {
  const _BenchmarkControls({
    required this.status,
    required this.message,
    required this.busy,
    required this.dateFormat,
    required this.onCpuSelected,
    required this.onGpuSelected,
    required this.onStop,
    required this.onRefresh,
  });

  final BenchmarkStatus? status;
  final String? message;
  final bool busy;
  final DateFormat dateFormat;
  final ValueChanged<BenchmarkKind> onCpuSelected;
  final VoidCallback onGpuSelected;
  final VoidCallback onStop;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final state = status?.state ?? 'idle';
    final running = status?.isRunning ?? false;
    final locked = busy || running;
    final label = status?.label ?? 'No benchmark running';
    return SectionCard(
      title: 'Benchmarks',
      trailing: StatusBadge(
        label: _benchmarkStateLabel(state),
        tone: _benchmarkTone(state),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label),
          if (message != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(message!),
          ],
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              PopupMenuButton<BenchmarkKind>(
                enabled: !locked,
                onSelected: onCpuSelected,
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: BenchmarkKind.cpuSingle,
                    child: Text('Single-Core Benchmark'),
                  ),
                  PopupMenuItem(
                    value: BenchmarkKind.cpuMulti,
                    child: Text('Multi-Core Benchmark'),
                  ),
                  PopupMenuItem(
                    value: BenchmarkKind.cpuStress,
                    child: Text('CPU Stress Test'),
                  ),
                ],
                child: _BenchmarkMenuButton(
                  icon: Icons.memory,
                  label: busy ? 'Working...' : 'CPU Benchmark',
                  enabled: !locked,
                ),
              ),
              FilledButton.icon(
                onPressed: locked ? null : onGpuSelected,
                icon: const Icon(Icons.speed),
                label: const Text('GPU Vulkan Benchmark'),
              ),
              OutlinedButton.icon(
                onPressed: running && !busy ? onStop : null,
                icon: const Icon(Icons.stop_circle),
                label: const Text('Stop Running Test'),
              ),
              OutlinedButton.icon(
                onPressed: busy ? null : onRefresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh status'),
              ),
            ],
          ),
          if (status != null) ...[
            const SizedBox(height: AppSpacing.md),
            _BenchmarkDetails(status: status!, dateFormat: dateFormat),
          ],
        ],
      ),
    );
  }
}

class _BenchmarkMenuButton extends StatelessWidget {
  const _BenchmarkMenuButton({
    required this.icon,
    required this.label,
    required this.enabled,
  });

  final IconData icon;
  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final foreground = enabled
        ? Theme.of(context).colorScheme.onPrimary
        : Theme.of(context).disabledColor;
    final background = enabled
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).disabledColor.withValues(alpha: 0.12);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: foreground),
            const SizedBox(width: AppSpacing.sm),
            Text(label, style: TextStyle(color: foreground)),
            const SizedBox(width: AppSpacing.xs),
            Icon(Icons.arrow_drop_down, color: foreground),
          ],
        ),
      ),
    );
  }
}

class _BenchmarkDetails extends StatelessWidget {
  const _BenchmarkDetails({required this.status, required this.dateFormat});

  final BenchmarkStatus status;
  final DateFormat dateFormat;

  @override
  Widget build(BuildContext context) {
    final outputText = [
      if (status.stdoutTail.isNotEmpty) ...['stdout', ...status.stdoutTail],
      if (status.stderrTail.isNotEmpty) ...[
        if (status.stdoutTail.isNotEmpty) '',
        'stderr',
        ...status.stderrTail,
      ],
    ].join('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            _InfoPill(label: 'Server cores', value: status.nproc.toString()),
            if (status.startedAt != null)
              _InfoPill(
                label: 'Started',
                value: dateFormat.format(status.startedAt!.toLocal()),
              ),
            if (status.durationSeconds != null)
              _InfoPill(label: 'Duration', value: '${status.durationSeconds}s'),
            if (status.threads != null)
              _InfoPill(label: 'Threads', value: status.threads.toString()),
            if (status.workers != null)
              _InfoPill(label: 'Workers', value: status.workers.toString()),
            if (status.returnCode != null)
              _InfoPill(
                label: 'Exit code',
                value: status.returnCode.toString(),
              ),
          ],
        ),
        if (status.result.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Text('Result', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final entry in status.result.entries)
                _InfoPill(
                  label: _humanizeKey(entry.key),
                  value: _formatResultValue(entry.value),
                ),
            ],
          ),
        ],
        if (status.command.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Text('Command', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpacing.xs),
          SelectableText(status.command.join(' ')),
        ],
        if (outputText.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Output tail'),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: SelectableText(
                  outputText,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text('$label: $value'),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _BenchmarkSettingsDialog extends StatefulWidget {
  const _BenchmarkSettingsDialog({
    required this.title,
    required this.durationLabel,
    required this.durationDefault,
    required this.durationMin,
    required this.durationMax,
    required this.secondaryLabel,
    required this.secondaryDefault,
    required this.secondaryMin,
    required this.secondaryMax,
  });

  final String title;
  final String durationLabel;
  final int durationDefault;
  final int durationMin;
  final int durationMax;
  final String? secondaryLabel;
  final int? secondaryDefault;
  final int? secondaryMin;
  final int? secondaryMax;

  @override
  State<_BenchmarkSettingsDialog> createState() =>
      _BenchmarkSettingsDialogState();
}

class _BenchmarkSettingsDialogState extends State<_BenchmarkSettingsDialog> {
  late final TextEditingController _durationController;
  late final TextEditingController? _secondaryController;
  String? _error;

  @override
  void initState() {
    super.initState();
    _durationController = TextEditingController(
      text: widget.durationDefault.toString(),
    );
    _secondaryController = widget.secondaryDefault == null
        ? null
        : TextEditingController(text: widget.secondaryDefault.toString());
  }

  @override
  void dispose() {
    _durationController.dispose();
    _secondaryController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _durationController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: widget.durationLabel,
                helperText:
                    'Min ${widget.durationMin}, max ${widget.durationMax}',
              ),
            ),
            if (_secondaryController != null) ...[
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _secondaryController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: widget.secondaryLabel,
                  helperText:
                      'Min ${widget.secondaryMin}, max ${widget.secondaryMax}',
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(_error!, style: TextStyle(color: Colors.red.shade300)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Start')),
      ],
    );
  }

  void _submit() {
    final duration = _readClamped(
      _durationController.text,
      widget.durationMin,
      widget.durationMax,
    );
    final secondary = _secondaryController == null
        ? null
        : _readClamped(
            _secondaryController.text,
            widget.secondaryMin!,
            widget.secondaryMax!,
          );
    if (duration == null ||
        (_secondaryController != null && secondary == null)) {
      setState(() => _error = 'Enter numeric values in the allowed range.');
      return;
    }
    Navigator.of(context).pop(
      _BenchmarkSettingsResult(
        durationSeconds: duration,
        secondaryValue: secondary,
      ),
    );
  }

  int? _readClamped(String rawValue, int min, int max) {
    final value = int.tryParse(rawValue.trim());
    if (value == null) {
      return null;
    }
    return value.clamp(min, max).toInt();
  }
}

class _BenchmarkSettingsResult {
  const _BenchmarkSettingsResult({
    required this.durationSeconds,
    required this.secondaryValue,
  });

  final int durationSeconds;
  final int? secondaryValue;
}

String _benchmarkStateLabel(String state) {
  return switch (state) {
    'running' => 'Running',
    'finished' => 'Finished',
    'failed' => 'Failed',
    'stopped' => 'Stopped',
    _ => 'Idle',
  };
}

StatusTone _benchmarkTone(String state) {
  return switch (state) {
    'running' => StatusTone.warning,
    'finished' => StatusTone.healthy,
    'failed' => StatusTone.critical,
    'stopped' => StatusTone.offline,
    _ => StatusTone.unknown,
  };
}

String _humanizeKey(String key) {
  return key
      .split('_')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

String _formatResultValue(Object? value) {
  return switch (value) {
    double item => item.toStringAsFixed(item >= 100 ? 1 : 2),
    num item => item.toString(),
    bool item => item ? 'yes' : 'no',
    _ => value?.toString() ?? '-',
  };
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
