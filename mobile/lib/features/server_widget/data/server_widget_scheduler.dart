import 'package:workmanager/workmanager.dart';

const serverWidgetPeriodicTaskUniqueName = 'server_widget_periodic_refresh';
const serverWidgetPeriodicTaskName = 'server_widget_periodic_refresh';
const serverWidgetManualTaskUniqueName = 'server_widget_manual_refresh';
const serverWidgetManualTaskName = 'server_widget_manual_refresh';

abstract class BackgroundTaskScheduler {
  Future<void> registerPeriodicTask({
    required String uniqueName,
    required String taskName,
    required Duration frequency,
    required Constraints constraints,
    required ExistingPeriodicWorkPolicy existingWorkPolicy,
  });

  Future<void> registerOneOffTask({
    required String uniqueName,
    required String taskName,
    required Constraints constraints,
    required ExistingWorkPolicy existingWorkPolicy,
  });
}

class WorkmanagerBackgroundTaskScheduler implements BackgroundTaskScheduler {
  const WorkmanagerBackgroundTaskScheduler();

  @override
  Future<void> registerPeriodicTask({
    required String uniqueName,
    required String taskName,
    required Duration frequency,
    required Constraints constraints,
    required ExistingPeriodicWorkPolicy existingWorkPolicy,
  }) {
    return Workmanager().registerPeriodicTask(
      uniqueName,
      taskName,
      frequency: frequency,
      constraints: constraints,
      existingWorkPolicy: existingWorkPolicy,
    );
  }

  @override
  Future<void> registerOneOffTask({
    required String uniqueName,
    required String taskName,
    required Constraints constraints,
    required ExistingWorkPolicy existingWorkPolicy,
  }) {
    return Workmanager().registerOneOffTask(
      uniqueName,
      taskName,
      constraints: constraints,
      existingWorkPolicy: existingWorkPolicy,
    );
  }
}

class ServerWidgetScheduler {
  const ServerWidgetScheduler({
    BackgroundTaskScheduler scheduler =
        const WorkmanagerBackgroundTaskScheduler(),
  }) : _scheduler = scheduler;

  final BackgroundTaskScheduler _scheduler;

  static int normalizeRefreshMinutes(int value) {
    if (const {15, 30, 60}.contains(value)) {
      return value;
    }
    return 15;
  }

  Future<void> schedulePeriodicRefresh(int refreshMinutes) async {
    await _scheduler.registerPeriodicTask(
      uniqueName: serverWidgetPeriodicTaskUniqueName,
      taskName: serverWidgetPeriodicTaskName,
      frequency: Duration(minutes: normalizeRefreshMinutes(refreshMinutes)),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    );
  }

  Future<void> enqueueManualRefresh() async {
    await _scheduler.registerOneOffTask(
      uniqueName: serverWidgetManualTaskUniqueName,
      taskName: serverWidgetManualTaskName,
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
  }
}
