import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../../../../core/config/app_settings.dart';
import '../../../../core/networking/dio_factory.dart';
import '../../dashboard/data/monitoring_api_client.dart';
import '../../dashboard/domain/models/monitoring_models.dart';
import '../domain/models/server_widget_snapshot.dart';
import 'server_widget_catalog.dart';
import 'server_widget_routes.dart';
import 'server_widget_scheduler.dart';

const serverWidgetSnapshotKey = 'server_widget_snapshot';
const serverWidgetShowNetworkRowKey = 'server_widget_show_network_row';
const serverWidgetStorageMountpointKey = 'server_widget_storage_mountpoint';
const serverWidgetSecondaryStorageMountpointKey =
    'server_widget_secondary_storage_mountpoint';
const serverWidgetShowSecondaryStorageKey =
    'server_widget_show_secondary_storage';

@pragma('vm:entry-point')
void serverWidgetWorkmanagerDispatcher() {
  WidgetsFlutterBinding.ensureInitialized();
  Workmanager().executeTask((task, inputData) async {
    return ServerWidgetService.instance.runBackgroundRefreshTask();
  });
}

@pragma('vm:entry-point')
Future<void> serverWidgetInteractiveCallback(Uri? uri) async {
  WidgetsFlutterBinding.ensureInitialized();
  await ServerWidgetService.instance.handleInteractiveIntent(uri);
}

class ServerWidgetService {
  ServerWidgetService({
    ServerWidgetScheduler scheduler = const ServerWidgetScheduler(),
  }) : _scheduler = scheduler;

  static final instance = ServerWidgetService();

  final ServerWidgetScheduler _scheduler;
  bool _bootstrapped = false;

  Future<void> bootstrap() async {
    if (!Platform.isAndroid || _bootstrapped) {
      return;
    }
    await Workmanager().initialize(serverWidgetWorkmanagerDispatcher);
    await HomeWidget.registerInteractivityCallback(
      serverWidgetInteractiveCallback,
    );
    _bootstrapped = true;
  }

  Future<String?> readInitialLaunchRoute() async {
    if (!Platform.isAndroid) {
      return null;
    }
    return routeForWidgetUri(
      await HomeWidget.initiallyLaunchedFromHomeWidget(),
    );
  }

  Stream<String> widgetLaunchRoutes() {
    if (!Platform.isAndroid) {
      return const Stream<String>.empty();
    }
    return HomeWidget.widgetClicked.asyncExpand((uri) async* {
      final route = routeForWidgetUri(uri);
      if (route != null) {
        yield route;
      }
    });
  }

  Future<void> syncSettings(AppSettings settings) async {
    if (!Platform.isAndroid) {
      return;
    }
    await _persistWidgetConfig(settings);
    await _scheduler.schedulePeriodicRefresh(
      settings.widgetBackgroundRefreshMinutes,
    );
    await _updateWidget();
  }

  Future<void> updateFromLiveData({
    required SummaryResponse summary,
    required SystemResponse system,
    required AppSettings settings,
    required DateTime updatedAt,
    GpuResponse? gpu,
  }) async {
    if (!Platform.isAndroid ||
        !settings.onboardingComplete ||
        settings.monitoringApiUrl.trim().isEmpty) {
      return;
    }

    final previous = await _readStoredSnapshot();
    final snapshot = ServerWidgetSnapshot.fromMonitoringData(
      summary: summary,
      system: system,
      settings: settings,
      updatedAt: updatedAt,
      gpu: gpu,
      previous: previous,
    );
    await _persistSnapshot(snapshot, settings: settings);
  }

  Future<bool> runBackgroundRefreshTask() async {
    if (!Platform.isAndroid) {
      return true;
    }

    final preferences = await SharedPreferences.getInstance();
    final settings = loadAppSettings(preferences);
    final previous = await _readStoredSnapshot();

    if (!settings.onboardingComplete ||
        settings.monitoringApiUrl.trim().isEmpty) {
      final snapshot = ServerWidgetSnapshot.offlineFromPrevious(
        previous: previous,
      );
      await _persistSnapshot(snapshot, settings: settings);
      return true;
    }

    try {
      final client = MonitoringApiClient(
        DioFactory.create(
          baseUrl: settings.monitoringApiUrl,
          showTiming: settings.showRequestTiming,
        ),
      );
      final summary = await client.getSummary();
      final system = await client.getSystem();
      GpuResponse? gpu;
      try {
        gpu = await client.getGpu();
      } catch (_) {
        gpu = null;
      }

      final snapshot = ServerWidgetSnapshot.fromMonitoringData(
        summary: summary,
        system: system,
        settings: settings,
        updatedAt: DateTime.now(),
        gpu: gpu,
        previous: previous,
      );
      await _persistSnapshot(snapshot, settings: settings);
    } catch (_) {
      final snapshot = ServerWidgetSnapshot.offlineFromPrevious(
        previous: previous,
        fallbackHostname: previous?.hostname ?? 'Homelab Server',
      );
      await _persistSnapshot(snapshot, settings: settings);
    }

    // Keep the task successful to avoid aggressive retry loops.
    return true;
  }

  Future<void> handleInteractiveIntent(Uri? uri) async {
    if (!Platform.isAndroid) {
      return;
    }
    if (widgetActionFromUri(uri) == 'refresh') {
      await _scheduler.enqueueManualRefresh();
    }
  }

  Future<void> _persistSnapshot(
    ServerWidgetSnapshot snapshot, {
    required AppSettings settings,
  }) async {
    await _persistWidgetConfig(settings);
    await HomeWidget.saveWidgetData<String>(
      serverWidgetSnapshotKey,
      jsonEncode(snapshot.toJson()),
    );
    await _updateWidget();
  }

  Future<void> _persistWidgetConfig(AppSettings settings) async {
    await HomeWidget.saveWidgetData<bool>(
      serverWidgetShowNetworkRowKey,
      settings.widgetShowNetworkThroughput,
    );
    await HomeWidget.saveWidgetData<String>(
      serverWidgetStorageMountpointKey,
      settings.widgetStorageMountpoint,
    );
    await HomeWidget.saveWidgetData<String>(
      serverWidgetSecondaryStorageMountpointKey,
      settings.widgetSecondaryStorageMountpoint,
    );
    await HomeWidget.saveWidgetData<bool>(
      serverWidgetShowSecondaryStorageKey,
      settings.widgetShowSecondaryStorage,
    );
  }

  Future<ServerWidgetSnapshot?> _readStoredSnapshot() async {
    final raw = await HomeWidget.getWidgetData<String>(
      serverWidgetSnapshotKey,
      defaultValue: null,
    );
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    try {
      return ServerWidgetSnapshot.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _updateWidget() async {
    for (final providerName in homeScreenWidgetProviderNames) {
      await HomeWidget.updateWidget(name: providerName);
    }
  }
}
