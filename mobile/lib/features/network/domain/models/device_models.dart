class DevicesDashboard {
  const DevicesDashboard({required this.devices});

  final List<KnownDevice> devices;
}

class KnownDevice {
  const KnownDevice({
    required this.id,
    required this.name,
    required this.category,
    required this.lanIp,
    required this.tailscaleIp,
    required this.online,
    required this.latencyMs,
    required this.lastChecked,
    required this.lastSeen,
    required this.wolEnabled,
    required this.wakeAction,
    required this.notes,
    required this.tailscaleHostName,
    required this.tailscaleDnsName,
    required this.tailscaleOs,
    required this.tailscaleOnline,
    required this.tailscaleLastSeen,
    required this.probeSummary,
    required this.probes,
  });

  final String id;
  final String name;
  final String category;
  final String? lanIp;
  final String? tailscaleIp;
  final bool online;
  final double? latencyMs;
  final DateTime? lastChecked;
  final DateTime? lastSeen;
  final bool wolEnabled;
  final String? wakeAction;
  final String? notes;
  final String? tailscaleHostName;
  final String? tailscaleDnsName;
  final String? tailscaleOs;
  final bool? tailscaleOnline;
  final DateTime? tailscaleLastSeen;
  final String probeSummary;
  final List<DeviceProbeResult> probes;

  factory KnownDevice.fromJson(Map<String, dynamic> json) {
    return KnownDevice(
      id: json['id'] as String? ?? 'unknown',
      name: json['name'] as String? ?? 'Unknown device',
      category: json['category'] as String? ?? 'other',
      lanIp: json['lan_ip'] as String?,
      tailscaleIp: json['tailscale_ip'] as String?,
      online: json['online'] as bool? ?? false,
      latencyMs: (json['latency_ms'] as num?)?.toDouble(),
      lastChecked: _parseDateTime(json['last_checked']),
      lastSeen: _parseDateTime(json['last_seen']),
      wolEnabled: json['wol_enabled'] as bool? ?? false,
      wakeAction: json['wake_action'] as String?,
      notes: json['notes'] as String?,
      tailscaleHostName: json['tailscale_host_name'] as String?,
      tailscaleDnsName: json['tailscale_dns_name'] as String?,
      tailscaleOs: json['tailscale_os'] as String?,
      tailscaleOnline: json['tailscale_online'] as bool?,
      tailscaleLastSeen: _parseDateTime(json['tailscale_last_seen']),
      probeSummary: json['probe_summary'] as String? ?? 'No probes',
      probes: [
        for (final probe in (json['probes'] as List<dynamic>? ?? const []))
          DeviceProbeResult.fromJson(probe as Map<String, dynamic>),
      ],
    );
  }

  String? get preferredIp => tailscaleIp ?? lanIp;
}

class DeviceProbeResult {
  const DeviceProbeResult({
    required this.type,
    required this.label,
    required this.port,
    required this.reachable,
    required this.latencyMs,
    required this.summary,
  });

  final String type;
  final String label;
  final int? port;
  final bool reachable;
  final double? latencyMs;
  final String summary;

  factory DeviceProbeResult.fromJson(Map<String, dynamic> json) {
    return DeviceProbeResult(
      type: json['type'] as String? ?? 'unknown',
      label: json['label'] as String? ?? 'Probe',
      port: json['port'] as int?,
      reachable: json['reachable'] as bool? ?? false,
      latencyMs: (json['latency_ms'] as num?)?.toDouble(),
      summary: json['summary'] as String? ?? '',
    );
  }
}

DateTime? _parseDateTime(Object? value) {
  final text = value as String?;
  if (text == null || text.isEmpty) {
    return null;
  }
  return DateTime.tryParse(text);
}
