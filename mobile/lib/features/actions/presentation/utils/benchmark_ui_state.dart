import 'package:flutter/material.dart';

import '../../../../core/widgets/status_tone.dart';
import '../../domain/models/benchmark_models.dart';

enum BenchmarkUiState {
  idle,
  running,
  finished,
  failed,
  stopped,
  unavailable,
  authError,
  unreachable,
}

class BenchmarkNotice {
  const BenchmarkNotice(this.message, {this.stateOverride, this.rawDetail});

  final String message;
  final BenchmarkUiState? stateOverride;
  final String? rawDetail;
}

class BenchmarkResultEntry {
  const BenchmarkResultEntry(this.label, this.value);

  final String label;
  final String value;
}

BenchmarkNotice benchmarkNoticeForStatus(
  BenchmarkStatus status, {
  String? startedLabel,
  String? fallbackMessage,
}) {
  final state = benchmarkStateFromApiValue(status.state);
  if (state == BenchmarkUiState.running) {
    final label = startedLabel ?? status.label ?? 'Benchmark';
    return BenchmarkNotice(
      '$label is running. Status refreshes automatically.',
    );
  }
  if (state == BenchmarkUiState.finished) {
    return const BenchmarkNotice(
      'Benchmark finished. Results are shown below.',
    );
  }
  if (state == BenchmarkUiState.stopped) {
    return BenchmarkNotice(fallbackMessage ?? 'Benchmark stopped.');
  }
  if (state == BenchmarkUiState.failed) {
    final rawDetail = status.detail;
    final unavailable = looksBenchmarkUnavailable(rawDetail);
    return BenchmarkNotice(
      unavailable
          ? 'Benchmark tool is unavailable on the control agent.'
          : status.kind == BenchmarkKind.gpuVkmark
          ? 'GPU benchmark failed. Open details for command output.'
          : 'Benchmark failed. Open details for command output.',
      stateOverride: unavailable
          ? BenchmarkUiState.unavailable
          : BenchmarkUiState.failed,
      rawDetail: rawDetail,
    );
  }
  return const BenchmarkNotice('Choose a CPU or GPU benchmark to run.');
}

BenchmarkUiState benchmarkUiState(
  BenchmarkStatus? status,
  BenchmarkNotice? notice,
) {
  return notice?.stateOverride ?? benchmarkStateFromApiValue(status?.state);
}

BenchmarkUiState benchmarkStateFromApiValue(String? state) {
  return switch (state) {
    'running' => BenchmarkUiState.running,
    'finished' => BenchmarkUiState.finished,
    'failed' => BenchmarkUiState.failed,
    'stopped' => BenchmarkUiState.stopped,
    _ => BenchmarkUiState.idle,
  };
}

String benchmarkStateLabel(BenchmarkUiState state) {
  return switch (state) {
    BenchmarkUiState.running => 'Running',
    BenchmarkUiState.finished => 'Finished',
    BenchmarkUiState.failed => 'Failed',
    BenchmarkUiState.stopped => 'Stopped',
    BenchmarkUiState.unavailable => 'Unavailable',
    BenchmarkUiState.authError => 'Auth error',
    BenchmarkUiState.unreachable => 'Unreachable',
    BenchmarkUiState.idle => 'Idle',
  };
}

String benchmarkDefaultMessage(BenchmarkUiState state) {
  return switch (state) {
    BenchmarkUiState.running =>
      'Benchmark is running. Status refreshes automatically.',
    BenchmarkUiState.finished => 'Benchmark finished. Results are shown below.',
    BenchmarkUiState.failed =>
      'Benchmark failed. Open details for command output.',
    BenchmarkUiState.stopped => 'Benchmark stopped.',
    BenchmarkUiState.unavailable =>
      'Benchmark endpoints are unavailable. Update/restart the control agent.',
    BenchmarkUiState.authError => 'Control-agent token missing or invalid.',
    BenchmarkUiState.unreachable => 'Control agent unreachable.',
    BenchmarkUiState.idle => 'Choose a CPU or GPU benchmark to run.',
  };
}

StatusTone benchmarkTone(BenchmarkUiState state) {
  return switch (state) {
    BenchmarkUiState.running => StatusTone.warning,
    BenchmarkUiState.finished => StatusTone.healthy,
    BenchmarkUiState.failed => StatusTone.critical,
    BenchmarkUiState.stopped => StatusTone.offline,
    BenchmarkUiState.unavailable => StatusTone.warning,
    BenchmarkUiState.authError => StatusTone.critical,
    BenchmarkUiState.unreachable => StatusTone.offline,
    BenchmarkUiState.idle => StatusTone.unknown,
  };
}

IconData benchmarkStateIcon(StatusTone tone) {
  return switch (tone) {
    StatusTone.healthy => Icons.check_circle,
    StatusTone.warning => Icons.hourglass_top,
    StatusTone.critical => Icons.error_outline,
    StatusTone.offline => Icons.power_off,
    StatusTone.unknown || StatusTone.neutral => Icons.speed,
  };
}

bool benchmarkServiceBlocked(BenchmarkUiState state) {
  return switch (state) {
    BenchmarkUiState.unavailable ||
    BenchmarkUiState.authError ||
    BenchmarkUiState.unreachable => true,
    _ => false,
  };
}

bool hasBenchmarkDetails(BenchmarkStatus? status, String? rawDetail) {
  return rawDetail?.trim().isNotEmpty == true ||
      status?.returnCode != null ||
      (status?.command.isNotEmpty ?? false) ||
      (status?.stdoutTail.isNotEmpty ?? false) ||
      (status?.stderrTail.isNotEmpty ?? false);
}

String? benchmarkRawDetail(BenchmarkStatus? status, BenchmarkNotice? notice) {
  return notice?.rawDetail ?? status?.detail;
}

bool looksBenchmarkUnavailable(String? detail) {
  final value = detail?.toLowerCase() ?? '';
  return value.contains('unavailable') ||
      value.contains('not found') ||
      value.contains('no such file') ||
      value.contains('missing');
}

List<BenchmarkResultEntry> benchmarkResultEntries(BenchmarkStatus status) {
  final result = status.result;
  final orderedKeys = switch (status.kind) {
    BenchmarkKind.gpuVkmark => ['score'],
    BenchmarkKind.cpuSingle || BenchmarkKind.cpuMulti => [
      'events_per_second',
      'total_events',
      'total_time_seconds',
    ],
    BenchmarkKind.cpuStress => [
      'passed',
      'failed',
      'bogo_ops',
      'bogo_ops_per_second',
      'real_time_seconds',
    ],
    null => result.keys.toList(growable: false),
  };
  final emitted = <String>{};
  return [
    for (final key in orderedKeys)
      if (result.containsKey(key) && emitted.add(key))
        BenchmarkResultEntry(
          _resultLabel(key),
          formatBenchmarkResultValue(key, result[key]),
        ),
    for (final entry in result.entries)
      if (emitted.add(entry.key))
        BenchmarkResultEntry(
          _humanizeKey(entry.key),
          formatBenchmarkResultValue(entry.key, entry.value),
        ),
  ];
}

String formatBenchmarkResultValue(String key, Object? value) {
  return switch ((key, value)) {
    ('events_per_second', num item) => '${_formatNumber(item)}/s',
    ('bogo_ops_per_second', num item) => '${_formatNumber(item)}/s',
    ('total_time_seconds', num item) => '${_formatNumber(item)}s',
    ('real_time_seconds', num item) => '${_formatNumber(item)}s',
    (_, double item) => _formatNumber(item),
    (_, num item) => item.toString(),
    (_, bool item) => item ? 'yes' : 'no',
    _ => value?.toString() ?? '-',
  };
}

String _resultLabel(String key) {
  return switch (key) {
    'score' => 'Vulkan score',
    'events_per_second' => 'Events/sec',
    'total_events' => 'Total events',
    'total_time_seconds' => 'Total time',
    'bogo_ops' => 'Bogo ops',
    'bogo_ops_per_second' => 'Bogo ops/sec',
    'real_time_seconds' => 'Real time',
    'passed' => 'Passed',
    'failed' => 'Failed',
    _ => _humanizeKey(key),
  };
}

String _humanizeKey(String key) {
  return key
      .split('_')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

String _formatNumber(num value) {
  final number = value.toDouble();
  if (number >= 100 || number == number.roundToDouble()) {
    return number.toStringAsFixed(number == number.roundToDouble() ? 0 : 1);
  }
  return number.toStringAsFixed(2);
}
