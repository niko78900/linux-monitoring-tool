import 'package:flutter_test/flutter_test.dart';
import 'package:homelab_tablet/features/hosts/domain/models/host_models.dart';
import 'package:homelab_tablet/features/network/domain/models/device_models.dart';
import 'package:homelab_tablet/features/services/domain/models/service_models.dart';

void main() {
  test('ManagedService json keeps defaults and converters', () {
    final service = ManagedService.fromJson({
      'service_id': 'jellyfin',
      'display_name': 'Jellyfin',
      'runtime_type': 'docker',
      'ports': [8096, '8920'],
      'allowed_actions': ['restart', 42],
      'last_checked': '2026-06-20T10:15:00Z',
      'last_action': {
        'service_id': 'jellyfin',
        'action': 'restart',
        'status': 'success',
        'requested_at': '2026-06-20T10:16:00Z',
      },
    });

    expect(service.hostId, 'unknown');
    expect(service.runtimeAdapter, 'docker');
    expect(service.ports, ['8096', '8920']);
    expect(service.allowedActions, ['restart', '42']);
    expect(service.lastChecked, DateTime.parse('2026-06-20T10:15:00Z'));
    expect(service.lastAction?.requestedAt, isNotNull);

    final defaults = ManagedService.fromJson({});
    expect(defaults.serviceId, 'unknown');
    expect(defaults.displayName, 'Unknown service');
    expect(defaults.ports, isEmpty);
    expect(defaults.lastAction, isNull);
  });

  test('KnownDevice json keeps Tailscale fields and probe defaults', () {
    final device = KnownDevice.fromJson({
      'id': 'main-pc',
      'name': 'Main PC',
      'online': true,
      'latency_ms': 12,
      'last_checked': '2026-06-20T11:00:00Z',
      'tailscale_host_name': 'main-pc',
      'tailscale_online': true,
      'probes': [
        {
          'type': 'tcp',
          'label': 'RDP',
          'port': 3389,
          'reachable': true,
          'latency_ms': 3,
        },
        'ignored',
      ],
    });

    expect(device.category, 'other');
    expect(device.online, isTrue);
    expect(device.latencyMs, 12);
    expect(device.tailscaleHostName, 'main-pc');
    expect(device.probes, hasLength(1));
    expect(device.probes.single.summary, '');

    final defaults = KnownDevice.fromJson({});
    expect(defaults.id, 'unknown');
    expect(defaults.name, 'Unknown device');
    expect(defaults.probeSummary, 'No probes');
  });

  test('ManagedHost json preserves availability fallback and list parsing', () {
    final host = ManagedHost.fromJson({
      'id': 'server',
      'display_name': 'Homelab Server',
      'online': true,
      'status': 'unexpected',
      'capabilities': ['terminal', 42],
      'services': ['jellyfin'],
      'tags': ['homelab'],
      'probes': [
        {
          'type': 'tcp',
          'label': 'SSH',
          'port': 22,
          'reachable': true,
          'latency_ms': 1.5,
        },
      ],
    });

    expect(host.status, HostAvailability.online);
    expect(host.capabilities, ['terminal', '42']);
    expect(host.services, ['jellyfin']);
    expect(host.tags, ['homelab']);
    expect(host.probes.single.summary, '');

    final defaults = ManagedHost.fromJson({});
    expect(defaults.id, 'unknown');
    expect(defaults.enabled, isTrue);
    expect(defaults.status, HostAvailability.unknown);
    expect(defaults.probeSummary, 'No probes');
  });
}
