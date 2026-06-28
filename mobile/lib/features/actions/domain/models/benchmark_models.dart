enum BenchmarkKind {
  cpuSingle('cpu_single', 'Single-Core Benchmark'),
  cpuMulti('cpu_multi', 'Multi-Core Benchmark'),
  cpuStress('cpu_stress', 'CPU Stress Test'),
  gpuVkmark('gpu_vkmark', 'GPU Vulkan Benchmark');

  const BenchmarkKind(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static BenchmarkKind? fromApiValue(String? value) {
    for (final kind in values) {
      if (kind.apiValue == value) {
        return kind;
      }
    }
    return null;
  }
}

class BenchmarkStartRequest {
  const BenchmarkStartRequest({
    required this.kind,
    this.durationSeconds,
    this.threads,
    this.workers,
  });

  final BenchmarkKind kind;
  final int? durationSeconds;
  final int? threads;
  final int? workers;

  Map<String, Object?> toJson() {
    return {
      'kind': kind.apiValue,
      if (durationSeconds != null) 'duration_seconds': durationSeconds,
      if (threads != null) 'threads': threads,
      if (workers != null) 'workers': workers,
    };
  }
}

class BenchmarkStatus {
  const BenchmarkStatus({
    required this.state,
    required this.kind,
    required this.label,
    required this.startedAt,
    required this.finishedAt,
    required this.durationSeconds,
    required this.threads,
    required this.workers,
    required this.command,
    required this.returnCode,
    required this.result,
    required this.stdoutTail,
    required this.stderrTail,
    required this.detail,
    required this.nproc,
    required this.gpuHelperPath,
    required this.gpuHelperAvailable,
  });

  factory BenchmarkStatus.fromJson(Map<String, dynamic> json) {
    return BenchmarkStatus(
      state: json['state'] as String? ?? 'idle',
      kind: BenchmarkKind.fromApiValue(json['kind'] as String?),
      label: json['label'] as String?,
      startedAt: _parseDateTime(json['started_at']),
      finishedAt: _parseDateTime(json['finished_at']),
      durationSeconds: _parseInt(json['duration_seconds']),
      threads: _parseInt(json['threads']),
      workers: _parseInt(json['workers']),
      command: _stringList(json['command']),
      returnCode: _parseInt(json['return_code']),
      result: Map<String, Object?>.from(
        json['result'] as Map<String, dynamic>? ?? const <String, dynamic>{},
      ),
      stdoutTail: _stringList(json['stdout_tail']),
      stderrTail: _stringList(json['stderr_tail']),
      detail: json['detail'] as String?,
      nproc: _parseInt(json['nproc']) ?? 1,
      gpuHelperPath: json['gpu_helper_path'] as String? ?? '',
      gpuHelperAvailable: json['gpu_helper_available'] as bool? ?? false,
    );
  }

  final String state;
  final BenchmarkKind? kind;
  final String? label;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final int? durationSeconds;
  final int? threads;
  final int? workers;
  final List<String> command;
  final int? returnCode;
  final Map<String, Object?> result;
  final List<String> stdoutTail;
  final List<String> stderrTail;
  final String? detail;
  final int nproc;
  final String gpuHelperPath;
  final bool gpuHelperAvailable;

  bool get isRunning => state == 'running';
}

DateTime? _parseDateTime(Object? value) {
  final text = value as String?;
  return text == null || text.isEmpty ? null : DateTime.tryParse(text);
}

int? _parseInt(Object? value) {
  return switch (value) {
    int item => item,
    num item => item.toInt(),
    String item => int.tryParse(item),
    _ => null,
  };
}

List<String> _stringList(Object? value) {
  return [
    for (final item in value is List<dynamic> ? value : const <dynamic>[])
      item.toString(),
  ];
}
