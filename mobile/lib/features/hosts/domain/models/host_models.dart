class ManagedHostsDashboard {
  const ManagedHostsDashboard({required this.hosts});

  final List<ManagedHost> hosts;
}

class ManagedHost {
  const ManagedHost({
    required this.id,
    required this.displayName,
    required this.category,
    required this.description,
    required this.lanIp,
    required this.tailscaleIp,
    required this.tailscaleHostname,
    required this.monitoringApiUrl,
    required this.controlApiUrl,
    required this.enabled,
    required this.online,
    required this.status,
    required this.latencyMs,
    required this.lastChecked,
    required this.lastSeen,
    required this.capabilities,
    required this.services,
    required this.tags,
    required this.probes,
    required this.probeSummary,
  });

  factory ManagedHost.fromJson(Map<String, dynamic> json) {
    return ManagedHost(
      id: json['id'] as String? ?? 'unknown',
      displayName: json['display_name'] as String? ?? 'Unknown host',
      category: json['category'] as String? ?? 'other',
      description: json['description'] as String?,
      lanIp: json['lan_ip'] as String?,
      tailscaleIp: json['tailscale_ip'] as String?,
      tailscaleHostname: json['tailscale_hostname'] as String?,
      monitoringApiUrl: json['monitoring_api_url'] as String?,
      controlApiUrl: json['control_api_url'] as String?,
      enabled: json['enabled'] as bool? ?? true,
      online: json['online'] as bool? ?? false,
      status: HostAvailability.fromJson(
        json['status'],
        online: json['online'] as bool?,
      ),
      latencyMs: (json['latency_ms'] as num?)?.toDouble(),
      lastChecked: _parseDateTime(json['last_checked']),
      lastSeen: _parseDateTime(json['last_seen']),
      capabilities: [
        for (final item in (json['capabilities'] as List<dynamic>? ?? const []))
          item.toString(),
      ],
      services: [
        for (final item in (json['services'] as List<dynamic>? ?? const []))
          item.toString(),
      ],
      tags: [
        for (final item in (json['tags'] as List<dynamic>? ?? const []))
          item.toString(),
      ],
      probes: [
        for (final item in (json['probes'] as List<dynamic>? ?? const []))
          HostProbeResult.fromJson(item as Map<String, dynamic>),
      ],
      probeSummary: json['probe_summary'] as String? ?? 'No probes',
    );
  }

  final String id;
  final String displayName;
  final String category;
  final String? description;
  final String? lanIp;
  final String? tailscaleIp;
  final String? tailscaleHostname;
  final String? monitoringApiUrl;
  final String? controlApiUrl;
  final bool enabled;
  final bool online;
  final HostAvailability status;
  final double? latencyMs;
  final DateTime? lastChecked;
  final DateTime? lastSeen;
  final List<String> capabilities;
  final List<String> services;
  final List<String> tags;
  final List<HostProbeResult> probes;
  final String probeSummary;

  String? get preferredIp => tailscaleIp ?? lanIp;
}

enum HostAvailability {
  online('Online'),
  unreachable('Unreachable'),
  unknown('Unknown');

  const HostAvailability(this.label);

  final String label;

  static HostAvailability fromJson(Object? value, {bool? online}) {
    final raw = value?.toString().trim().toLowerCase();
    return switch (raw) {
      'online' => HostAvailability.online,
      'unreachable' || 'offline' => HostAvailability.unreachable,
      'unknown' || 'not_checked' || 'not checked' => HostAvailability.unknown,
      _ =>
        online == true
            ? HostAvailability.online
            : online == false
            ? HostAvailability.unreachable
            : HostAvailability.unknown,
    };
  }
}

class HostProbeResult {
  const HostProbeResult({
    required this.type,
    required this.label,
    required this.port,
    required this.reachable,
    required this.latencyMs,
    required this.summary,
  });

  factory HostProbeResult.fromJson(Map<String, dynamic> json) {
    return HostProbeResult(
      type: json['type'] as String? ?? 'unknown',
      label: json['label'] as String? ?? 'Probe',
      port: json['port'] as int?,
      reachable: json['reachable'] as bool? ?? false,
      latencyMs: (json['latency_ms'] as num?)?.toDouble(),
      summary: json['summary'] as String? ?? '',
    );
  }

  final String type;
  final String label;
  final int? port;
  final bool reachable;
  final double? latencyMs;
  final String summary;
}

DateTime? _parseDateTime(Object? value) {
  final text = value as String?;
  if (text == null || text.isEmpty) {
    return null;
  }
  return DateTime.tryParse(text);
}
