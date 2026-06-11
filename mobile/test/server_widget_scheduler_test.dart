import 'package:flutter_test/flutter_test.dart';
import 'package:homelab_tablet/features/server_widget/data/server_widget_routes.dart';
import 'package:homelab_tablet/features/server_widget/data/server_widget_scheduler.dart';
import 'package:workmanager/workmanager.dart';

void main() {
  test('widget route parser handles overview and storage links', () {
    expect(
      routeForWidgetUri(Uri.parse('homelabtablet://overview')),
      '/overview',
    );
    expect(
      routeForWidgetUri(Uri.parse('homelabtablet:///storage')),
      '/storage',
    );
    expect(routeForWidgetUri(Uri.parse('homelabtablet://unknown')), isNull);
  });

  test('refresh interval normalization enforces allowed values', () {
    expect(ServerWidgetScheduler.normalizeRefreshMinutes(15), 15);
    expect(ServerWidgetScheduler.normalizeRefreshMinutes(30), 30);
    expect(ServerWidgetScheduler.normalizeRefreshMinutes(60), 60);
    expect(ServerWidgetScheduler.normalizeRefreshMinutes(10), 15);
    expect(ServerWidgetScheduler.normalizeRefreshMinutes(45), 15);
  });

  test('manual refresh enqueue uses one-off worker contract', () async {
    final fake = _FakeBackgroundTaskScheduler();
    final scheduler = ServerWidgetScheduler(scheduler: fake);

    await scheduler.enqueueManualRefresh();

    expect(
      fake.oneOffCalls.single.uniqueName,
      serverWidgetManualTaskUniqueName,
    );
    expect(fake.oneOffCalls.single.taskName, serverWidgetManualTaskName);
    expect(
      fake.oneOffCalls.single.existingWorkPolicy,
      ExistingWorkPolicy.replace,
    );
  });
}

class _FakeBackgroundTaskScheduler implements BackgroundTaskScheduler {
  final List<_OneOffCall> oneOffCalls = [];
  final List<Object> periodicCalls = [];

  @override
  Future<void> registerOneOffTask({
    required String uniqueName,
    required String taskName,
    required Constraints constraints,
    required ExistingWorkPolicy existingWorkPolicy,
  }) async {
    oneOffCalls.add(
      _OneOffCall(
        uniqueName: uniqueName,
        taskName: taskName,
        existingWorkPolicy: existingWorkPolicy,
      ),
    );
  }

  @override
  Future<void> registerPeriodicTask({
    required String uniqueName,
    required String taskName,
    required Duration frequency,
    required Constraints constraints,
    required ExistingPeriodicWorkPolicy existingWorkPolicy,
  }) async {
    periodicCalls.add(Object());
  }
}

class _OneOffCall {
  const _OneOffCall({
    required this.uniqueName,
    required this.taskName,
    required this.existingWorkPolicy,
  });

  final String uniqueName;
  final String taskName;
  final ExistingWorkPolicy existingWorkPolicy;
}
