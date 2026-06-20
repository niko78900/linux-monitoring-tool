// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'host_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ManagedHost _$ManagedHostFromJson(Map<String, dynamic> json) => ManagedHost(
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
  status: _hostAvailabilityFromJson(_readHostAvailability(json, 'status')),
  latencyMs: _doubleFromJson(json['latency_ms']),
  lastChecked: _parseDateTime(json['last_checked']),
  lastSeen: _parseDateTime(json['last_seen']),
  capabilities: _stringListFromJson(json['capabilities']),
  services: _stringListFromJson(json['services']),
  tags: _stringListFromJson(json['tags']),
  probes: _hostProbeResultsFromJson(json['probes']),
  probeSummary: json['probe_summary'] as String? ?? 'No probes',
);

HostProbeResult _$HostProbeResultFromJson(Map<String, dynamic> json) =>
    HostProbeResult(
      type: json['type'] as String? ?? 'unknown',
      label: json['label'] as String? ?? 'Probe',
      port: _intFromJson(json['port']),
      reachable: json['reachable'] as bool? ?? false,
      latencyMs: _doubleFromJson(json['latency_ms']),
      summary: json['summary'] as String? ?? '',
    );
