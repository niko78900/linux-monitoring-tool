import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homelab_tablet/features/actions/domain/models/benchmark_models.dart';
import 'package:homelab_tablet/features/actions/presentation/utils/benchmark_error_mapper.dart';
import 'package:homelab_tablet/features/actions/presentation/utils/benchmark_ui_state.dart';
import 'package:homelab_tablet/features/actions/presentation/widgets/benchmark_controls.dart';
import 'package:homelab_tablet/features/actions/presentation/widgets/benchmark_details.dart';
import 'package:intl/intl.dart';

void main() {
  group('benchmark error mapping', () {
    test('maps auth failures to auth error', () {
      for (final statusCode in [401, 403]) {
        final notice = mapBenchmarkError(
          _dioError(statusCode: statusCode, detail: 'Unauthorized'),
        );

        expect(notice.stateOverride, BenchmarkUiState.authError);
        expect(notice.message, 'Control-agent token missing or invalid.');
        expect(notice.rawDetail, contains('Unauthorized'));
      }
    });

    test('maps 404 to unavailable endpoints', () {
      final notice = mapBenchmarkError(
        _dioError(statusCode: 404, detail: 'Not Found'),
      );

      expect(notice.stateOverride, BenchmarkUiState.unavailable);
      expect(
        notice.message,
        'Benchmark endpoints are unavailable. Update/restart the control agent.',
      );
      expect(notice.rawDetail, contains('Not Found'));
    });

    test('maps connection failures to unreachable', () {
      final notice = mapBenchmarkError(
        _dioError(
          type: DioExceptionType.connectionError,
          detail: 'SocketException',
        ),
      );

      expect(notice.stateOverride, BenchmarkUiState.unreachable);
      expect(notice.message, 'Control agent unreachable.');
    });

    test('maps helper unavailable failures to unavailable', () {
      final notice = mapBenchmarkError(
        _dioError(statusCode: 503, detail: 'GPU helper missing: no such file'),
      );

      expect(notice.stateOverride, BenchmarkUiState.unavailable);
      expect(
        notice.message,
        'Benchmark tool is unavailable on the control agent.',
      );
      expect(notice.rawDetail, contains('no such file'));
    });
  });

  group('benchmark status summaries', () {
    test('failed benchmark keeps raw output in details', () {
      final status = BenchmarkStatus.fromJson({
        'state': 'failed',
        'kind': 'gpu_vkmark',
        'label': 'GPU Vulkan Benchmark',
        'return_code': 1,
        'command': ['/usr/local/sbin/homelab-vkmark-benchmark', '800x600'],
        'stdout_tail': ['vkmark started'],
        'stderr_tail': ['sudo: a password is required'],
        'detail': 'benchmark command failed',
      });
      final notice = benchmarkNoticeForStatus(status);

      expect(notice.stateOverride, BenchmarkUiState.failed);
      expect(
        notice.message,
        'GPU benchmark failed. Open details for command output.',
      );
      expect(
        hasBenchmarkDetails(status, benchmarkRawDetail(status, notice)),
        isTrue,
      );
      expect(formatBenchmarkOutputTail(status), contains('stdout'));
      expect(formatBenchmarkOutputTail(status), contains('stderr'));
      expect(formatBenchmarkOutputTail(status), contains('sudo'));
    });

    test('finished GPU result shows score summary', () {
      final entries = benchmarkResultEntries(
        BenchmarkStatus.fromJson({
          'state': 'finished',
          'kind': 'gpu_vkmark',
          'result': {'score': 4581},
        }),
      );

      expect(entries, hasLength(1));
      expect(entries.single.label, 'Vulkan score');
      expect(entries.single.value, '4581');
    });

    test('finished CPU result shows events per second summary', () {
      final entries = benchmarkResultEntries(
        BenchmarkStatus.fromJson({
          'state': 'finished',
          'kind': 'cpu_multi',
          'result': {
            'events_per_second': 1234.5,
            'total_events': 37042,
            'total_time_seconds': 30.0012,
          },
        }),
      );

      expect(entries.map((entry) => entry.label), [
        'Events/sec',
        'Total events',
        'Total time',
      ]);
      expect(entries.first.value, '1234.5/s');
      expect(entries.last.value, '30.00s');
    });
  });

  testWidgets('running benchmark disables starts and enables stop', (
    tester,
  ) async {
    var cpuSelected = false;
    var gpuSelected = false;
    var stopped = false;
    final status = BenchmarkStatus.fromJson({
      'state': 'running',
      'kind': 'cpu_multi',
      'label': 'CPU Multi-Core Benchmark',
      'nproc': 16,
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BenchmarkControls(
            status: status,
            notice: benchmarkNoticeForStatus(status),
            busy: false,
            dateFormat: DateFormat.Hms(),
            onCpuSelected: (_) => cpuSelected = true,
            onGpuSelected: () => gpuSelected = true,
            onStop: () => stopped = true,
            onRefresh: () {},
          ),
        ),
      ),
    );

    final gpuButton = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('GPU Vulkan Benchmark'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(gpuButton.onPressed, isNull);

    final stopButton = tester.widget<OutlinedButton>(
      find.ancestor(
        of: find.text('Stop Running Test'),
        matching: find.byType(OutlinedButton),
      ),
    );
    expect(stopButton.onPressed, isNotNull);

    await tester.tap(find.text('Stop Running Test'));

    expect(stopped, isTrue);
    expect(cpuSelected, isFalse);
    expect(gpuSelected, isFalse);
  });
}

DioException _dioError({
  int? statusCode,
  String? detail,
  DioExceptionType type = DioExceptionType.badResponse,
}) {
  final requestOptions = RequestOptions(path: '/benchmarks/status');
  return DioException(
    requestOptions: requestOptions,
    type: type,
    message: detail,
    response: statusCode == null
        ? null
        : Response<Object?>(
            requestOptions: requestOptions,
            statusCode: statusCode,
            data: detail == null ? null : {'detail': detail},
          ),
  );
}
