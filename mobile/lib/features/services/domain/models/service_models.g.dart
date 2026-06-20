// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'service_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ManagedService _$ManagedServiceFromJson(Map<String, dynamic> json) =>
    ManagedService(
      serviceId: json['service_id'] as String? ?? 'unknown',
      displayName: json['display_name'] as String? ?? 'Unknown service',
      hostId: json['host_id'] as String? ?? 'unknown',
      runtimeAdapter: json['runtime_type'] as String? ?? 'unknown',
      runtimeTarget: json['runtime_target'] as String? ?? 'unknown',
      runtimeState: json['runtime_state'] as String? ?? 'unknown',
      healthProbeState: json['health_probe_state'] as String? ?? 'unknown',
      category: json['category'] as String? ?? 'service',
      description: json['description'] as String?,
      url: json['url'] as String?,
      ports: _stringListFromJson(json['ports']),
      image: json['image'] as String?,
      lastChecked: _parseDateTime(json['last_checked']),
      allowedActions: _stringListFromJson(json['allowed_actions']),
      lastAction: _serviceActionResultFromJson(json['last_action']),
    );

ServiceActionResult _$ServiceActionResultFromJson(Map<String, dynamic> json) =>
    ServiceActionResult(
      serviceId: json['service_id'] as String? ?? 'unknown',
      action: json['action'] as String? ?? 'unknown',
      status: json['status'] as String? ?? 'unknown',
      requestedAt: _parseDateTime(json['requested_at']),
      detail: json['detail'] as String?,
    );
