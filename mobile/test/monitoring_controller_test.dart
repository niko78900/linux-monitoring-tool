import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homelab_tablet/core/config/app_settings.dart';
import 'package:homelab_tablet/features/dashboard/data/monitoring_api_client.dart';
import 'package:homelab_tablet/features/dashboard/data/monitoring_repository.dart';
import 'package:homelab_tablet/features/dashboard/domain/models/monitoring_models.dart';
import 'package:homelab_tablet/features/dashboard/presentation/providers/monitoring_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('refreshAll appends GPU history only from the GPU endpoint', () async {
    final fakeClient = _FakeMonitoringApiClient();
    final container = await _container(fakeClient);
    addTearDown(container.dispose);

    await container.read(monitoringControllerProvider.notifier).refreshAll();

    final state = container.read(monitoringControllerProvider);
    expect(fakeClient.summaryCalls, 1);
    expect(fakeClient.gpuCalls, 1);
    expect(state.gpuUtilizationHistory, hasLength(1));
    expect(state.gpuUtilizationHistory.single.value, 80);
    expect(state.gpuTemperatureHistory, hasLength(1));
    expect(state.gpuTemperatureHistory.single.value, 61);
  });

  test(
    'duplicate endpoint calls share the existing in-flight request',
    () async {
      final fakeClient = _FakeMonitoringApiClient();
      final health = Completer<HealthResponse>();
      fakeClient.healthHandler = () => health.future;
      final container = await _container(fakeClient);
      addTearDown(container.dispose);
      final controller = container.read(monitoringControllerProvider.notifier);

      final first = controller.fetchHealth();
      await Future<void>.delayed(Duration.zero);
      final second = controller.fetchHealth();

      expect(fakeClient.healthCalls, 1);
      health.complete(_health());
      await Future.wait([first, second]);

      fakeClient.healthHandler = () async => _health();
      await controller.fetchHealth();
      expect(fakeClient.healthCalls, 2);
    },
  );

  test('in-flight guard clears after endpoint failure', () async {
    final fakeClient = _FakeMonitoringApiClient();
    final firstHealth = Completer<HealthResponse>();
    fakeClient.healthHandler = () => firstHealth.future;
    final container = await _container(fakeClient);
    addTearDown(container.dispose);
    final controller = container.read(monitoringControllerProvider.notifier);

    final first = controller.fetchHealth();
    await Future<void>.delayed(Duration.zero);
    firstHealth.completeError(Exception('offline'));
    await first;

    fakeClient.healthHandler = () async => _health();
    await controller.fetchHealth();
    expect(fakeClient.healthCalls, 2);
  });

  test('different endpoints may refresh concurrently', () async {
    final fakeClient = _FakeMonitoringApiClient();
    final summary = Completer<SummaryResponse>();
    final system = Completer<SystemResponse>();
    fakeClient.summaryHandler = () => summary.future;
    fakeClient.systemHandler = () => system.future;
    final container = await _container(fakeClient);
    addTearDown(container.dispose);
    final controller = container.read(monitoringControllerProvider.notifier);

    final summaryRequest = controller.fetchSummary();
    final systemRequest = controller.fetchSystem();
    await Future<void>.delayed(Duration.zero);

    expect(fakeClient.summaryCalls, 1);
    expect(fakeClient.systemCalls, 1);
    expect(summary.isCompleted, isFalse);
    expect(system.isCompleted, isFalse);

    summary.complete(_summary());
    system.complete(_system());
    await Future.wait([summaryRequest, systemRequest]);
  });
}

Future<ProviderContainer> _container(
  _FakeMonitoringApiClient fakeClient,
) async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(preferences),
      monitoringRepositoryProvider.overrideWithValue(
        MonitoringRepository(fakeClient),
      ),
    ],
  );
  container.read(monitoringControllerProvider);
  return container;
}

class _FakeMonitoringApiClient extends MonitoringApiClient {
  _FakeMonitoringApiClient() : super(Dio());

  int healthCalls = 0;
  int summaryCalls = 0;
  int systemCalls = 0;
  int gpuCalls = 0;
  int dockerCalls = 0;

  Future<HealthResponse> Function()? healthHandler;
  Future<SummaryResponse> Function()? summaryHandler;
  Future<SystemResponse> Function()? systemHandler;
  Future<GpuResponse> Function()? gpuHandler;
  Future<DockerResponse> Function()? dockerHandler;

  @override
  Future<HealthResponse> getHealth() {
    healthCalls += 1;
    return healthHandler?.call() ?? Future.value(_health());
  }

  @override
  Future<SummaryResponse> getSummary() {
    summaryCalls += 1;
    return summaryHandler?.call() ?? Future.value(_summary());
  }

  @override
  Future<SystemResponse> getSystem() {
    systemCalls += 1;
    return systemHandler?.call() ?? Future.value(_system());
  }

  @override
  Future<GpuResponse> getGpu() {
    gpuCalls += 1;
    return gpuHandler?.call() ?? Future.value(_gpu());
  }

  @override
  Future<DockerResponse> getDocker() {
    dockerCalls += 1;
    return dockerHandler?.call() ?? Future.value(_docker());
  }
}

HealthResponse _health() {
  return HealthResponse(
    status: 'ok',
    appName: 'test',
    version: 'test',
    timestamp: DateTime.utc(2026, 6, 12),
  );
}

SummaryResponse _summary() {
  return const SummaryResponse(
    hostname: 'homelab',
    uptimeHuman: '1h',
    cpuPercent: 12,
    memoryPercent: 34,
    diskPercent: 56,
    gpuAvailable: true,
    gpuUtilizationPercent: 20,
    gpuTempC: 44,
    dockerAvailable: true,
    runningContainers: 3,
  );
}

GpuResponse _gpu() {
  return const GpuResponse(
    available: true,
    reason: null,
    name: 'NVIDIA GeForce GTX 1070',
    temperatureC: 61,
    utilizationPercent: 80,
    memoryTotalMb: 8192,
    memoryUsedMb: 4096,
    memoryFreeMb: 4096,
    powerUsageW: 100,
    fanSpeedPercent: 40,
    driverVersion: '555',
  );
}

DockerResponse _docker() {
  return const DockerResponse(
    dockerAvailable: true,
    reason: null,
    containerCount: 0,
    containers: [],
  );
}

SystemResponse _system() {
  return SystemResponse.fromJson({
    'hostname': 'homelab',
    'os': {
      'system': 'Linux',
      'release': '6.0',
      'version': '1',
      'machine': 'x86_64',
      'platform': 'Debian GNU/Linux',
    },
    'kernel_version': '6.0',
    'uptime_seconds': 3600,
    'uptime_human': '1h',
    'cpu': {
      'usage_percent': 12,
      'physical_cores': 8,
      'logical_cores': 16,
      'temperature_c': 42,
      'load_average': {'one_min': 0.1, 'five_min': 0.2, 'fifteen_min': 0.3},
    },
    'memory': {'total': 32, 'available': 16, 'used': 16, 'percent': 50},
    'swap': {'total': 8, 'used': 1, 'percent': 12.5},
    'disk': {
      'total': 100,
      'used': 50,
      'free': 50,
      'percent': 50,
      'mountpoint': '/',
    },
    'specs': {
      'cpu': {
        'model_name': 'AMD Ryzen',
        'vendor': 'AuthenticAMD',
        'architecture': 'x86_64',
        'physical_cores': 8,
        'logical_cores': 16,
      },
      'memory_total_bytes': 32,
      'swap_total_bytes': 8,
      'memory': {'total_bytes': 32, 'manufacturers': [], 'modules': []},
      'motherboard': {},
      'gpu': {'available': true, 'capabilities': []},
    },
    'network': {
      'bytes_sent': 1,
      'bytes_recv': 1,
      'packets_sent': 1,
      'packets_recv': 1,
    },
  });
}
