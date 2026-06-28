import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homelab_tablet/core/config/app_settings.dart';
import 'package:homelab_tablet/features/actions/domain/models/benchmark_models.dart';
import 'package:homelab_tablet/features/actions/presentation/pages/actions_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('shows control-agent setup state when URL is missing', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'onboardingComplete': true,
      'controlApiUrl': '',
    });
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
        child: const MaterialApp(home: Scaffold(body: ActionsPage())),
      ),
    );

    await tester.pump();

    expect(find.text('Configure the control agent first'), findsOneWidget);
  });

  test('benchmark models parse status and serialize start request', () {
    final status = BenchmarkStatus.fromJson({
      'state': 'finished',
      'kind': 'cpu_multi',
      'label': 'CPU Multi-Core Benchmark',
      'started_at': '2026-06-28T12:00:00Z',
      'duration_seconds': 30,
      'threads': 16,
      'result': {'events_per_second': 1234.5},
      'stdout_tail': ['events per second: 1234.5'],
      'stderr_tail': [],
      'nproc': 16,
      'gpu_helper_path': '/usr/local/sbin/homelab-vkmark-benchmark',
      'gpu_helper_available': true,
    });

    expect(status.state, 'finished');
    expect(status.kind, BenchmarkKind.cpuMulti);
    expect(status.nproc, 16);
    expect(status.result['events_per_second'], 1234.5);

    final request = const BenchmarkStartRequest(
      kind: BenchmarkKind.cpuStress,
      durationSeconds: 60,
      workers: 8,
    );

    expect(request.toJson(), {
      'kind': 'cpu_stress',
      'duration_seconds': 60,
      'workers': 8,
    });
  });
}
