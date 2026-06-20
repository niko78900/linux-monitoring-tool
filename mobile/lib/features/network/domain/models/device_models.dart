import 'package:json_annotation/json_annotation.dart';

part 'device_models.g.dart';

class DevicesDashboard {
  const DevicesDashboard({required this.devices});

  final List<KnownDevice> devices;
}

@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
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

  @JsonKey(defaultValue: 'unknown')
  final String id;
  @JsonKey(defaultValue: 'Unknown device')
  final String name;
  @JsonKey(defaultValue: 'other')
  final String category;
  final String? lanIp;
  final String? tailscaleIp;
  @JsonKey(defaultValue: false)
  final bool online;
  @JsonKey(fromJson: _doubleFromJson)
  final double? latencyMs;
  @JsonKey(fromJson: _parseDateTime)
  final DateTime? lastChecked;
  @JsonKey(fromJson: _parseDateTime)
  final DateTime? lastSeen;
  @JsonKey(defaultValue: false)
  final bool wolEnabled;
  final String? wakeAction;
  final String? notes;
  final String? tailscaleHostName;
  final String? tailscaleDnsName;
  final String? tailscaleOs;
  final bool? tailscaleOnline;
  @JsonKey(fromJson: _parseDateTime)
  final DateTime? tailscaleLastSeen;
  @JsonKey(defaultValue: 'No probes')
  final String probeSummary;
  @JsonKey(fromJson: _deviceProbeResultsFromJson)
  final List<DeviceProbeResult> probes;

  factory KnownDevice.fromJson(Map<String, dynamic> json) =>
      _$KnownDeviceFromJson(json);

  String? get preferredIp => tailscaleIp ?? lanIp;
}

@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class DeviceProbeResult {
  const DeviceProbeResult({
    required this.type,
    required this.label,
    required this.port,
    required this.reachable,
    required this.latencyMs,
    required this.summary,
  });

  @JsonKey(defaultValue: 'unknown')
  final String type;
  @JsonKey(defaultValue: 'Probe')
  final String label;
  @JsonKey(fromJson: _intFromJson)
  final int? port;
  @JsonKey(defaultValue: false)
  final bool reachable;
  @JsonKey(fromJson: _doubleFromJson)
  final double? latencyMs;
  @JsonKey(defaultValue: '')
  final String summary;

  factory DeviceProbeResult.fromJson(Map<String, dynamic> json) =>
      _$DeviceProbeResultFromJson(json);
}

List<DeviceProbeResult> _deviceProbeResultsFromJson(Object? value) {
  return [
    for (final item in value is List<dynamic> ? value : const <dynamic>[])
      if (item is Map<String, dynamic>) DeviceProbeResult.fromJson(item),
  ];
}

double? _doubleFromJson(Object? value) =>
    value is num ? value.toDouble() : null;

int? _intFromJson(Object? value) => value is num ? value.toInt() : null;

DateTime? _parseDateTime(Object? value) {
  final text = value as String?;
  if (text == null || text.isEmpty) {
    return null;
  }
  return DateTime.tryParse(text);
}
