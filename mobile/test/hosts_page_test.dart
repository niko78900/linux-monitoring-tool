import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homelab_tablet/features/hosts/domain/models/host_models.dart';
import 'package:homelab_tablet/features/hosts/presentation/pages/hosts_page.dart';
import 'package:homelab_tablet/features/hosts/presentation/providers/host_providers.dart';

void main() {
  testWidgets('renders managed host inventory card', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          managedHostsProvider.overrideWith(
            (ref) async => ManagedHostsDashboard(hosts: [_host()]),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: HostsPage())),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Hosts'), findsOneWidget);
    expect(find.text('Homelab Server'), findsOneWidget);
    expect(find.text('Debian primary homelab server'), findsOneWidget);
    expect(find.text('hardware monitoring'), findsOneWidget);
    expect(find.text('History'), findsWidgets);
  });

  testWidgets('renders empty state when no managed hosts are configured', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          managedHostsProvider.overrideWith(
            (ref) async => const ManagedHostsDashboard(hosts: []),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: HostsPage())),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('No managed hosts configured'), findsOneWidget);
  });
}

ManagedHost _host() {
  return ManagedHost(
    id: 'homelab-server',
    displayName: 'Homelab Server',
    category: 'server',
    description: 'Debian primary homelab server',
    lanIp: '192.168.100.34',
    tailscaleIp: '100.64.10.22',
    tailscaleHostname: 'homelab-server',
    monitoringApiUrl: 'http://100.64.10.22:8000/api',
    controlApiUrl: 'http://100.64.10.22:4042/api',
    enabled: true,
    online: true,
    latencyMs: 1.2,
    lastChecked: DateTime.utc(2026, 6, 11, 20),
    lastSeen: DateTime.utc(2026, 6, 11, 20),
    capabilities: const [
      'hardware_monitoring',
      'history',
      'service_control',
    ],
    services: const ['jellyfin', 'hfs'],
    tags: const ['debian', 'primary'],
    probes: const [
      HostProbeResult(
        type: 'tcp',
        label: 'SSH',
        port: 22,
        reachable: true,
        latencyMs: 1.2,
        summary: 'SSH: reachable',
      ),
    ],
    probeSummary: 'SSH: reachable',
  );
}
