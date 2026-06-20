import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homelab_tablet/features/network/domain/models/device_models.dart';
import 'package:homelab_tablet/features/network/presentation/pages/devices_page.dart';
import 'package:homelab_tablet/features/network/presentation/providers/control_providers.dart';

void main() {
  testWidgets('devices page renders Tailscale peers without LAN neighbors', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          devicesDashboardProvider.overrideWith(
            (ref) async => DevicesDashboard(
              devices: [_tailscalePeer()],
              neighbors: const [],
              neighborsNotice: '',
            ),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: DevicesPage())),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('tablet-peer'), findsOneWidget);
    expect(find.text('100.64.10.99'), findsOneWidget);
    expect(find.text('Observed LAN Neighbors'), findsNothing);
  });
}

KnownDevice _tailscalePeer() {
  return KnownDevice(
    id: 'tailscale-tablet-peer',
    name: 'tablet-peer',
    category: 'other',
    lanIp: null,
    tailscaleIp: '100.64.10.99',
    online: true,
    latencyMs: null,
    lastChecked: DateTime.utc(2026, 6, 20, 10),
    lastSeen: DateTime.utc(2026, 6, 20, 10),
    wolEnabled: false,
    wakeAction: null,
    notes: 'Tailscale peer',
    probeSummary: 'Tailscale peer online',
    probes: const [],
  );
}
