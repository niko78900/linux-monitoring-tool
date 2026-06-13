import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homelab_tablet/core/errors/app_exception.dart';
import 'package:homelab_tablet/features/history/domain/models/history_models.dart';
import 'package:homelab_tablet/features/history/presentation/pages/history_page.dart';
import 'package:homelab_tablet/features/history/presentation/providers/history_providers.dart';
import 'package:homelab_tablet/features/history/presentation/widgets/history_chart.dart';

void main() {
  testWidgets('history page renders cached overview and range controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          historyRangesProvider.overrideWith((ref) async => _ranges()),
          historyInventoryProvider.overrideWith((ref) async => _inventory()),
          overviewHistoryProvider.overrideWith(
            (ref, range) async => _overviewCache(),
          ),
          storageHistoryProvider.overrideWith(
            (ref, params) async => _storageCache(params.mountpoint),
          ),
          diskHistoryProvider.overrideWith(
            (ref, params) async => _diskCache(params.device),
          ),
          raidHistoryProvider.overrideWith(
            (ref, params) async => _raidCache(params.arrayName),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: HistoryPage())),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('History'), findsOneWidget);
    expect(find.textContaining('Cached history'), findsWidgets);
    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('1h'), findsOneWidget);
    expect(find.text('24h'), findsOneWidget);
    expect(find.text('7d'), findsOneWidget);
    expect(find.text('30d'), findsOneWidget);
    expect(find.text('CPU Usage'), findsOneWidget);
    expect(find.text('GPU Temperature'), findsOneWidget);
    expect(find.text('GPU VRAM Used'), findsOneWidget);
    expect(find.text('GPU VRAM Used (MB)'), findsNothing);
    expect(find.text('Network Receive'), findsOneWidget);
  });

  testWidgets('history page shows loading state while overview is pending', (
    tester,
  ) async {
    final completer =
        Completer<CachedHistoryData<HistoryOverviewResponseModel>>();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          historyRangesProvider.overrideWith((ref) async => _ranges()),
          historyInventoryProvider.overrideWith((ref) async => _inventory()),
          overviewHistoryProvider.overrideWith(
            (ref, range) => completer.future,
          ),
          storageHistoryProvider.overrideWith(
            (ref, params) async => _storageCache(params.mountpoint),
          ),
          diskHistoryProvider.overrideWith(
            (ref, params) async => _diskCache(params.device),
          ),
          raidHistoryProvider.overrideWith(
            (ref, params) async => _raidCache(params.arrayName),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: HistoryPage())),
      ),
    );

    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsWidgets);
  });

  testWidgets('history page shows offline error state', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          historyRangesProvider.overrideWith((ref) async => _ranges()),
          historyInventoryProvider.overrideWith((ref) async => _inventory()),
          overviewHistoryProvider.overrideWith(
            (ref, range) async =>
                throw const AppException('Server unreachable'),
          ),
          storageHistoryProvider.overrideWith(
            (ref, params) async => _storageCache(params.mountpoint),
          ),
          diskHistoryProvider.overrideWith(
            (ref, params) async => _diskCache(params.device),
          ),
          raidHistoryProvider.overrideWith(
            (ref, params) async => _raidCache(params.arrayName),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: HistoryPage())),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('History unavailable'), findsOneWidget);
    expect(find.text('Server unreachable'), findsOneWidget);
  });

  testWidgets('history chart shows empty-state text for null-only data', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HistoryChart(
            title: 'CPU Usage',
            points: [
              HistoryChartPoint(timestamp: null, value: null),
              HistoryChartPoint(timestamp: null, value: null),
            ],
          ),
        ),
      ),
    );

    expect(find.text('CPU Usage: no history data'), findsOneWidget);
  });
}

HistoryRangesResponseModel _ranges() {
  return const HistoryRangesResponseModel(
    defaultRange: HistoryRangeValue.twentyFourHours,
    maxPointsCap: 360,
    ranges: [
      HistoryRangeDescriptor(
        range: HistoryRangeValue.oneHour,
        label: '1h',
        durationSeconds: 3600,
      ),
      HistoryRangeDescriptor(
        range: HistoryRangeValue.twentyFourHours,
        label: '24h',
        durationSeconds: 86400,
      ),
      HistoryRangeDescriptor(
        range: HistoryRangeValue.sevenDays,
        label: '7d',
        durationSeconds: 604800,
      ),
      HistoryRangeDescriptor(
        range: HistoryRangeValue.thirtyDays,
        label: '30d',
        durationSeconds: 2592000,
      ),
    ],
  );
}

HistoryInventory _inventory() {
  return const HistoryInventory(
    mountpoints: ['/', '/mnt/warm', '/mnt/storage'],
    diskDevices: ['/dev/sda'],
    raidArrays: ['md0'],
  );
}

CachedHistoryData<HistoryOverviewResponseModel> _overviewCache() {
  return CachedHistoryData(
    fromCache: true,
    cachedAt: DateTime.utc(2026, 6, 11, 19, 55),
    data: HistoryOverviewResponseModel(
      range: HistoryRangeValue.twentyFourHours,
      from: DateTime.utc(2026, 6, 10, 20),
      to: DateTime.utc(2026, 6, 11, 20),
      resolutionSeconds: 300,
      maxPoints: 360,
      points: [
        HistoryOverviewPoint(
          timestamp: DateTime.utc(2026, 6, 11, 19, 55),
          cpuPercentAvg: 18.2,
          cpuPercentMax: 30,
          cpuTemperatureCAvg: 43.1,
          cpuTemperatureCMax: 50,
          memoryPercentAvg: 54,
          swapPercentAvg: 2,
          gpuUtilizationPercentAvg: 7,
          gpuTemperatureCAvg: 47.5,
          gpuMemoryUsedMbAvg: 700,
          gpuPowerUsageWAvg: 40,
          networkRecvBytesPerSecondAvg: 2048,
          networkSendBytesPerSecondAvg: 512,
          runningContainersAvg: 5,
        ),
      ],
    ),
  );
}

CachedHistoryData<StorageHistoryResponseModel> _storageCache(
  String mountpoint,
) {
  return CachedHistoryData(
    fromCache: true,
    cachedAt: DateTime.utc(2026, 6, 11, 19, 55),
    data: StorageHistoryResponseModel(
      range: HistoryRangeValue.twentyFourHours,
      mountpoint: mountpoint,
      from: DateTime.utc(2026, 6, 10, 20),
      to: DateTime.utc(2026, 6, 11, 20),
      resolutionSeconds: 300,
      maxPoints: 360,
      points: [
        StorageHistoryPoint(
          timestamp: DateTime.utc(2026, 6, 11, 19, 55),
          usedBytesAvg: 10,
          freeBytesAvg: 5,
          totalBytesAvg: 15,
          percentAvg: 66.7,
          percentMax: 70,
          readOnlyAny: false,
          availableAny: true,
          healthStatus: 'healthy',
        ),
      ],
    ),
  );
}

CachedHistoryData<DiskHistoryResponseModel> _diskCache(String device) {
  return CachedHistoryData(
    fromCache: true,
    cachedAt: DateTime.utc(2026, 6, 11, 19, 55),
    data: DiskHistoryResponseModel(
      range: HistoryRangeValue.twentyFourHours,
      device: device,
      from: DateTime.utc(2026, 6, 10, 20),
      to: DateTime.utc(2026, 6, 11, 20),
      resolutionSeconds: 300,
      maxPoints: 360,
      points: [
        DiskHistoryPoint(
          timestamp: DateTime.utc(2026, 6, 11, 19, 55),
          temperatureCAvg: 39,
          healthStatus: 'healthy',
          kernelState: 'running',
        ),
      ],
    ),
  );
}

CachedHistoryData<RaidHistoryResponseModel> _raidCache(String arrayName) {
  return CachedHistoryData(
    fromCache: true,
    cachedAt: DateTime.utc(2026, 6, 11, 19, 55),
    data: RaidHistoryResponseModel(
      range: HistoryRangeValue.twentyFourHours,
      arrayName: arrayName,
      from: DateTime.utc(2026, 6, 10, 20),
      to: DateTime.utc(2026, 6, 11, 20),
      resolutionSeconds: 300,
      maxPoints: 360,
      points: [
        RaidHistoryPoint(
          timestamp: DateTime.utc(2026, 6, 11, 19, 55),
          activeDevicesAvg: 4,
          degradedDevicesAvg: 0,
          state: 'clean',
          syncAction: null,
          healthStatus: 'healthy',
        ),
      ],
    ),
  );
}
