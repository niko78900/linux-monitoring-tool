import 'package:flutter_test/flutter_test.dart';
import 'package:homelab_tablet/features/dashboard/domain/models/monitoring_models.dart';

void main() {
  test('summary parser tolerates partial payloads', () {
    final summary = SummaryResponse.fromJson({
      'hostname': 'server',
      'cpu_percent': 25,
      'gpu_available': false,
    });

    expect(summary.hostname, 'server');
    expect(summary.cpuPercent, 25);
    expect(summary.memoryPercent, 0);
    expect(summary.gpuUtilizationPercent, isNull);
  });

  test('system parser handles absent optional telemetry', () {
    final system = SystemResponse.fromJson({
      'hostname': 'server',
      'cpu': {'usage_percent': 12.5, 'physical_cores': 4, 'logical_cores': 8},
      'memory': {'total': 100, 'available': 40, 'used': 60, 'percent': 60},
      'swap': {'total': 0, 'used': 0, 'percent': 0},
      'disk': {
        'total': 10,
        'used': 5,
        'free': 5,
        'percent': 50,
        'mountpoint': '/',
      },
      'network': {
        'bytes_sent': 10,
        'bytes_recv': 20,
        'packets_sent': 1,
        'packets_recv': 2,
      },
    });

    expect(system.hostname, 'server');
    expect(system.cpu.temperatureC, isNull);
    expect(system.raidArrays, isEmpty);
    expect(system.physicalDisks, isEmpty);
    expect(system.network.bytesRecv, 20);
  });

  test('gpu parser exposes memory usage percent', () {
    final gpu = GpuResponse.fromJson({
      'available': true,
      'memory_total_mb': 1000,
      'memory_used_mb': 250,
    });

    expect(gpu.available, isTrue);
    expect(gpu.memoryUsedPercent, 25);
  });
}
