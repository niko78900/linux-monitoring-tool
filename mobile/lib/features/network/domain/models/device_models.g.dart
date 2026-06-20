// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'device_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

KnownDevice _$KnownDeviceFromJson(Map<String, dynamic> json) => KnownDevice(
  id: json['id'] as String? ?? 'unknown',
  name: json['name'] as String? ?? 'Unknown device',
  category: json['category'] as String? ?? 'other',
  lanIp: json['lan_ip'] as String?,
  tailscaleIp: json['tailscale_ip'] as String?,
  online: json['online'] as bool? ?? false,
  latencyMs: _doubleFromJson(json['latency_ms']),
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
  probes: _deviceProbeResultsFromJson(json['probes']),
);

DeviceProbeResult _$DeviceProbeResultFromJson(Map<String, dynamic> json) =>
    DeviceProbeResult(
      type: json['type'] as String? ?? 'unknown',
      label: json['label'] as String? ?? 'Probe',
      port: _intFromJson(json['port']),
      reachable: json['reachable'] as bool? ?? false,
      latencyMs: _doubleFromJson(json['latency_ms']),
      summary: json['summary'] as String? ?? '',
    );
