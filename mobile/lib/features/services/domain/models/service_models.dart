import 'package:json_annotation/json_annotation.dart';

part 'service_models.g.dart';

@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class ManagedService {
  const ManagedService({
    required this.serviceId,
    required this.displayName,
    required this.hostId,
    required this.runtimeAdapter,
    required this.runtimeTarget,
    required this.runtimeState,
    required this.healthProbeState,
    required this.category,
    required this.description,
    required this.url,
    required this.ports,
    required this.image,
    required this.lastChecked,
    required this.allowedActions,
    required this.lastAction,
  });

  factory ManagedService.fromJson(Map<String, dynamic> json) =>
      _$ManagedServiceFromJson(json);

  @JsonKey(defaultValue: 'unknown')
  final String serviceId;
  @JsonKey(defaultValue: 'Unknown service')
  final String displayName;
  @JsonKey(defaultValue: 'unknown')
  final String hostId;
  @JsonKey(name: 'runtime_type', defaultValue: 'unknown')
  final String runtimeAdapter;
  @JsonKey(defaultValue: 'unknown')
  final String runtimeTarget;
  @JsonKey(defaultValue: 'unknown')
  final String runtimeState;
  @JsonKey(defaultValue: 'unknown')
  final String healthProbeState;
  @JsonKey(defaultValue: 'service')
  final String category;
  final String? description;
  final String? url;
  @JsonKey(fromJson: _stringListFromJson)
  final List<String> ports;
  final String? image;
  @JsonKey(fromJson: _parseDateTime)
  final DateTime? lastChecked;
  @JsonKey(fromJson: _stringListFromJson)
  final List<String> allowedActions;
  @JsonKey(fromJson: _serviceActionResultFromJson)
  final ServiceActionResult? lastAction;

  bool allows(String action) => allowedActions.contains(action);
}

@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class ServiceActionResult {
  const ServiceActionResult({
    required this.serviceId,
    required this.action,
    required this.status,
    required this.requestedAt,
    required this.detail,
  });

  factory ServiceActionResult.fromJson(Map<String, dynamic> json) =>
      _$ServiceActionResultFromJson(json);

  @JsonKey(defaultValue: 'unknown')
  final String serviceId;
  @JsonKey(defaultValue: 'unknown')
  final String action;
  @JsonKey(defaultValue: 'unknown')
  final String status;
  @JsonKey(fromJson: _parseDateTime)
  final DateTime? requestedAt;
  final String? detail;
}

List<String> _stringListFromJson(Object? value) {
  return [
    for (final item in value is List<dynamic> ? value : const <dynamic>[])
      item.toString(),
  ];
}

ServiceActionResult? _serviceActionResultFromJson(Object? value) {
  return value is Map<String, dynamic>
      ? ServiceActionResult.fromJson(value)
      : null;
}

DateTime? _parseDateTime(Object? value) {
  final text = value as String?;
  if (text == null || text.isEmpty) {
    return null;
  }
  return DateTime.tryParse(text);
}
