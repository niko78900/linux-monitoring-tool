class ManagedService {
  const ManagedService({
    required this.serviceId,
    required this.displayName,
    required this.hostId,
    required this.runtimeAdapter,
    required this.runtimeState,
    required this.healthProbeState,
    required this.lastChecked,
    required this.allowedActions,
    required this.lastAction,
  });

  factory ManagedService.fromJson(Map<String, dynamic> json) {
    return ManagedService(
      serviceId: json['service_id'] as String? ?? 'unknown',
      displayName: json['display_name'] as String? ?? 'Unknown service',
      hostId: json['host_id'] as String? ?? 'unknown',
      runtimeAdapter: json['runtime_type'] as String? ?? 'unknown',
      runtimeState: json['runtime_state'] as String? ?? 'unknown',
      healthProbeState: json['health_probe_state'] as String? ?? 'unknown',
      lastChecked: _parseDateTime(json['last_checked']),
      allowedActions: [
        for (final item in (json['allowed_actions'] as List<dynamic>? ?? const []))
          item.toString(),
      ],
      lastAction: json['last_action'] is Map<String, dynamic>
          ? ServiceActionResult.fromJson(json['last_action'] as Map<String, dynamic>)
          : null,
    );
  }

  final String serviceId;
  final String displayName;
  final String hostId;
  final String runtimeAdapter;
  final String runtimeState;
  final String healthProbeState;
  final DateTime? lastChecked;
  final List<String> allowedActions;
  final ServiceActionResult? lastAction;

  bool allows(String action) => allowedActions.contains(action);
}

class ServiceActionResult {
  const ServiceActionResult({
    required this.serviceId,
    required this.action,
    required this.status,
    required this.requestedAt,
    required this.detail,
  });

  factory ServiceActionResult.fromJson(Map<String, dynamic> json) {
    return ServiceActionResult(
      serviceId: json['service_id'] as String? ?? 'unknown',
      action: json['action'] as String? ?? 'unknown',
      status: json['status'] as String? ?? 'unknown',
      requestedAt: _parseDateTime(json['requested_at']),
      detail: json['detail'] as String?,
    );
  }

  final String serviceId;
  final String action;
  final String status;
  final DateTime? requestedAt;
  final String? detail;
}

DateTime? _parseDateTime(Object? value) {
  final text = value as String?;
  if (text == null || text.isEmpty) {
    return null;
  }
  return DateTime.tryParse(text);
}
