import 'package:flutter_test/flutter_test.dart';
import 'package:homelab_tablet/features/history/domain/models/history_models.dart';

void main() {
  test('history overview parser tolerates partial and null fields', () {
    final overview = HistoryOverviewResponseModel.fromJson({
      'range': '7d',
      'resolution_seconds': 300,
      'max_points': 180,
      'points': [
        {
          'timestamp': '2026-06-11T18:00:00Z',
          'cpu_percent_avg': 14.5,
          'cpu_percent_max': 30,
          'memory_percent_avg': 61,
          'network_recv_bytes_per_second_avg': 1024,
        },
        {'timestamp': '2026-06-11T18:05:00Z', 'cpu_percent_avg': null},
      ],
    });

    expect(overview.range, HistoryRangeValue.sevenDays);
    expect(overview.resolutionSeconds, 300);
    expect(overview.points, hasLength(2));
    expect(overview.points.first.cpuPercentAvg, 14.5);
    expect(overview.points.first.networkRecvBytesPerSecondAvg, 1024);
    expect(overview.points.last.cpuPercentAvg, isNull);
    expect(overview.points.last.gpuTemperatureCAvg, isNull);
  });

  test('storage and raid parsers map state booleans and counters', () {
    final storage = StorageHistoryResponseModel.fromJson({
      'range': '24h',
      'mountpoint': '/mnt/storage',
      'points': [
        {
          'timestamp': '2026-06-11T19:00:00Z',
          'used_bytes_avg': 100,
          'free_bytes_avg': 50,
          'percent_avg': 66.7,
          'read_only_any': true,
          'available_any': false,
          'health_status': 'warning',
        },
      ],
    });
    final raid = RaidHistoryResponseModel.fromJson({
      'range': '24h',
      'array_name': 'md0',
      'points': [
        {
          'timestamp': '2026-06-11T19:00:00Z',
          'active_devices_avg': 4,
          'degraded_devices_avg': 1,
          'state': 'clean',
          'sync_action': 'resync',
          'health_status': 'warning',
        },
      ],
    });

    expect(storage.mountpoint, '/mnt/storage');
    expect(storage.points.single.readOnlyAny, isTrue);
    expect(storage.points.single.availableAny, isFalse);
    expect(raid.arrayName, 'md0');
    expect(raid.points.single.degradedDevicesAvg, 1);
    expect(raid.points.single.syncAction, 'resync');
  });
}
