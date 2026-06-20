import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homelab_tablet/features/dashboard/domain/models/monitoring_models.dart';
import 'package:homelab_tablet/features/dashboard/domain/models/resource_state.dart';
import 'package:homelab_tablet/features/dashboard/presentation/providers/monitoring_controller.dart';
import 'package:homelab_tablet/features/history/domain/models/history_models.dart';
import 'package:homelab_tablet/features/history/presentation/providers/history_providers.dart';
import 'package:homelab_tablet/features/network/presentation/pages/network_page.dart';

void main() {
  testWidgets('network page renders range buttons and history charts', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          monitoringControllerProvider.overrideWith(
            _FakeMonitoringController.new,
          ),
          historyRangesProvider.overrideWith((ref) async => _ranges()),
          overviewHistoryProvider.overrideWith(
            (ref, range) async => CachedHistoryData(
              data: _overview(range),
              fromCache: false,
              cachedAt: null,
            ),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: NetworkPage())),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Known Devices'), findsNothing);
    expect(find.text('Live'), findsOneWidget);
    expect(find.text('Day'), findsOneWidget);
    expect(find.text('Week'), findsOneWidget);
    expect(find.text('Month'), findsOneWidget);

    await tester.tap(find.text('Day'));
    await tester.pumpAndSettle();

    expect(find.text('Historical throughput'), findsOneWidget);
    expect(find.text('Receive Throughput'), findsOneWidget);
    expect(find.text('Transmit Throughput'), findsOneWidget);
  });
}

class _FakeMonitoringController extends MonitoringController {
  @override
  MonitoringState build() {
    return MonitoringState.initial().copyWith(
      system: ResourceState<SystemResponse>.initial().success(_system()),
    );
  }

  @override
  Future<void> fetchSystem() async {}
}

HistoryRangesResponseModel _ranges() {
  return const HistoryRangesResponseModel(
    defaultRange: HistoryRangeValue.twentyFourHours,
    maxPointsCap: 360,
    ranges: [
      HistoryRangeDescriptor(
        range: HistoryRangeValue.twentyFourHours,
        label: '24h',
        durationSeconds: 86400,
      ),
    ],
  );
}

HistoryOverviewResponseModel _overview(HistoryRangeValue range) {
  final start = DateTime.utc(2026, 6, 20);
  return HistoryOverviewResponseModel(
    range: range,
    from: start,
    to: start.add(const Duration(hours: 24)),
    resolutionSeconds: 300,
    maxPoints: 360,
    points: [
      HistoryOverviewPoint(
        timestamp: start,
        cpuPercentAvg: null,
        cpuPercentMax: null,
        cpuTemperatureCAvg: null,
        cpuTemperatureCMax: null,
        memoryPercentAvg: null,
        swapPercentAvg: null,
        gpuUtilizationPercentAvg: null,
        gpuTemperatureCAvg: null,
        gpuMemoryUsedMbAvg: null,
        gpuPowerUsageWAvg: null,
        networkRecvBytesPerSecondAvg: 1024,
        networkSendBytesPerSecondAvg: 512,
        runningContainersAvg: null,
      ),
    ],
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
      'usage_percent': 12.0,
      'physical_cores': 8,
      'logical_cores': 16,
      'load_average': {'one_min': 0.1, 'five_min': 0.2, 'fifteen_min': 0.3},
    },
    'memory': {'total': 100, 'available': 50, 'used': 50, 'percent': 50},
    'swap': {'total': 8, 'used': 1, 'percent': 12.5},
    'disk': {'total': 100, 'used': 50, 'free': 50, 'percent': 50},
    'specs': {
      'cpu': {'model_name': 'CPU', 'architecture': 'x86_64'},
      'memory': {'total_bytes': 100, 'modules': []},
      'motherboard': {},
      'gpu': {'available': false, 'capabilities': []},
    },
    'network': {
      'bytes_sent': 2048,
      'bytes_recv': 4096,
      'packets_sent': 3,
      'packets_recv': 4,
      'top_speed_mbps': 1000,
    },
  });
}
