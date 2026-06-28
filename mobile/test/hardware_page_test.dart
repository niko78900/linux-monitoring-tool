import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homelab_tablet/features/dashboard/domain/models/monitoring_models.dart';
import 'package:homelab_tablet/features/dashboard/domain/models/resource_state.dart';
import 'package:homelab_tablet/features/dashboard/presentation/providers/monitoring_controller.dart';
import 'package:homelab_tablet/features/hardware/presentation/pages/hardware_page.dart';

void main() {
  testWidgets('hardware page scrolls to final motherboard row', (tester) async {
    tester.view.physicalSize = const Size(1180, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          monitoringControllerProvider.overrideWith(
            _FakeMonitoringController.new,
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: HardwarePage())),
      ),
    );

    await tester.pump();

    expect(find.text('Server'), findsOneWidget);
    expect(find.text('Debian 13'), findsOneWidget);
    expect(find.text('Linux 6.12'), findsOneWidget);
    expect(find.text('Intel Core i5-13400F'), findsOneWidget);

    await tester.tap(find.byTooltip('Show raw OS value'));
    await tester.pumpAndSettle();

    expect(
      find.text('Linux-6.12.90+deb13.1-amd64-x86_64-with-glibc2.41'),
      findsOneWidget,
    );

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Chipset'),
      240,
      scrollable: find.byType(Scrollable),
    );
    await tester.pumpAndSettle();

    expect(find.text('Chipset'), findsOneWidget);
    expect(find.text('B550'), findsOneWidget);
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

SystemResponse _system() {
  return SystemResponse.fromJson({
    'hostname': 'server',
    'os': {
      'system': 'Linux',
      'release': '6.12.90+deb13.1-amd64',
      'version': '1',
      'machine': 'x86_64',
      'platform': 'Linux-6.12.90+deb13.1-amd64-x86_64-with-glibc2.41',
    },
    'kernel_version': '6.12.90+deb13.1-amd64',
    'uptime_seconds': 3600,
    'uptime_human': '1h',
    'cpu': {
      'usage_percent': 12.0,
      'physical_cores': 8,
      'logical_cores': 16,
      'temperature_c': 41,
      'load_average': {'one_min': 0.1, 'five_min': 0.2, 'fifteen_min': 0.3},
    },
    'memory': {
      'total': 32 * 1024 * 1024 * 1024,
      'available': 16 * 1024 * 1024 * 1024,
      'used': 16 * 1024 * 1024 * 1024,
      'percent': 50,
    },
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
        'model_name': '13th Gen Intel(R) Core(TM) i5-13400F',
        'vendor': 'GenuineIntel',
        'architecture': 'x86_64',
        'physical_cores': 8,
        'logical_cores': 16,
        'capabilities': [
          for (var index = 0; index < 48; index += 1) 'capability_$index',
        ],
      },
      'memory_total_bytes': 32 * 1024 * 1024 * 1024,
      'swap_total_bytes': 8,
      'memory': {
        'total_bytes': 32 * 1024 * 1024 * 1024,
        'memory_type': 'DDR4',
        'speed_mhz': 3200,
        'manufacturers': ['Kingston'],
        'modules': [
          {
            'slot': 'DIMM A1',
            'manufacturer': 'Kingston',
            'memory_type': 'DDR4',
            'size_bytes': 16 * 1024 * 1024 * 1024,
            'speed_mhz': 3200,
          },
          {
            'slot': 'DIMM B1',
            'manufacturer': 'Kingston',
            'memory_type': 'DDR4',
            'size_bytes': 16 * 1024 * 1024 * 1024,
            'speed_mhz': 3200,
          },
        ],
      },
      'motherboard': {
        'vendor': 'Gigabyte',
        'model': 'Aorus',
        'version': '1.0',
        'chipset': 'B550',
      },
      'gpu': {'available': false, 'capabilities': []},
    },
    'network': {
      'bytes_sent': 1,
      'bytes_recv': 1,
      'packets_sent': 1,
      'packets_recv': 1,
    },
  });
}
