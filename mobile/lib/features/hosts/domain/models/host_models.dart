import 'package:json_annotation/json_annotation.dart';

part 'host_models.g.dart';

class ManagedHostsDashboard {
  const ManagedHostsDashboard({required this.hosts});

  final List<ManagedHost> hosts;
}

@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
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

  factory ManagedHost.fromJson(Map<String, dynamic> json) =>
      _$ManagedHostFromJson(json);

  @JsonKey(defaultValue: 'unknown')
  final String id;
  @JsonKey(defaultValue: 'Unknown host')
  final String displayName;
  @JsonKey(defaultValue: 'other')
  final String category;
  final String? description;
  final String? lanIp;
  final String? tailscaleIp;
  final String? tailscaleHostname;
  final String? monitoringApiUrl;
  final String? controlApiUrl;
  @JsonKey(defaultValue: true)
  final bool enabled;
  @JsonKey(defaultValue: false)
  final bool online;
  @JsonKey(
    readValue: _readHostAvailability,
    fromJson: _hostAvailabilityFromJson,
  )
  final HostAvailability status;
  @JsonKey(fromJson: _doubleFromJson)
  final double? latencyMs;
  @JsonKey(fromJson: _parseDateTime)
  final DateTime? lastChecked;
  @JsonKey(fromJson: _parseDateTime)
  final DateTime? lastSeen;
  @JsonKey(fromJson: _stringListFromJson)
  final List<String> capabilities;
  @JsonKey(fromJson: _stringListFromJson)
  final List<String> services;
  @JsonKey(fromJson: _stringListFromJson)
  final List<String> tags;
  @JsonKey(fromJson: _hostProbeResultsFromJson)
  final List<HostProbeResult> probes;
  @JsonKey(defaultValue: 'No probes')
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
      _ => online == true ? HostAvailability.online : HostAvailability.unknown,
    };
  }
}

@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class HostProbeResult {
  const HostProbeResult({
    required this.type,
    required this.label,
    required this.port,
    required this.reachable,
    required this.latencyMs,
    required this.summary,
  });

  factory HostProbeResult.fromJson(Map<String, dynamic> json) =>
      _$HostProbeResultFromJson(json);

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
}

Object? _readHostAvailability(Map json, String key) {
  final raw = json[key];
  final normalized = raw?.toString().trim().toLowerCase();
  final known = const {
    'online',
    'unreachable',
    'offline',
    'unknown',
    'not_checked',
    'not checked',
  };
  if (known.contains(normalized)) {
    return raw;
  }
  return json['online'] == true ? 'online' : raw;
}

HostAvailability _hostAvailabilityFromJson(Object? value) {
  return HostAvailability.fromJson(value);
}

List<String> _stringListFromJson(Object? value) {
  return [
    for (final item in value is List<dynamic> ? value : const <dynamic>[])
      item.toString(),
  ];
}

List<HostProbeResult> _hostProbeResultsFromJson(Object? value) {
  return [
    for (final item in value is List<dynamic> ? value : const <dynamic>[])
      if (item is Map<String, dynamic>) HostProbeResult.fromJson(item),
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
