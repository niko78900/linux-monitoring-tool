import '../../../../core/config/app_settings.dart';
import '../../../dashboard/domain/models/monitoring_models.dart';

class ServerWidgetSnapshot {
  const ServerWidgetSnapshot({
    required this.hostname,
    required this.serverReachable,
    required this.lastUpdatedUtc,
    required this.isStale,
    required this.cpuPercent,
    required this.cpuTemperatureC,
    required this.memoryPercent,
    required this.gpuAvailable,
    required this.gpuUtilizationPercent,
    required this.gpuTemperatureC,
    required this.primaryDiskPercent,
    required this.primaryDiskLabel,
    required this.primaryDiskFreeBytes,
    required this.secondaryDiskPercent,
    required this.secondaryDiskLabel,
    required this.secondaryDiskFreeBytes,
    required this.raidHealth,
    required this.diskHealth,
    required this.networkRecvBytesPerSecond,
    required this.networkSendBytesPerSecond,
    required this.networkBytesRecvTotal,
    required this.networkBytesSentTotal,
    required this.topNetworkSpeedMbps,
    required this.sourceNetworkBytesRecvTotal,
    required this.sourceNetworkBytesSentTotal,
  });

  factory ServerWidgetSnapshot.fromJson(Map<String, dynamic> json) {
    return ServerWidgetSnapshot(
      hostname: _string(json['hostname'], fallback: 'Homelab Server'),
      serverReachable: _bool(json['server_reachable']),
      lastUpdatedUtc: _date(json['last_updated_utc']),
      isStale: _bool(json['is_stale']),
      cpuPercent: _doubleOrNull(json['cpu_percent']),
      cpuTemperatureC: _doubleOrNull(json['cpu_temperature_c']),
      memoryPercent: _doubleOrNull(json['memory_percent']),
      gpuAvailable: _bool(json['gpu_available']),
      gpuUtilizationPercent: _doubleOrNull(json['gpu_utilization_percent']),
      gpuTemperatureC: _doubleOrNull(json['gpu_temperature_c']),
      primaryDiskPercent: _doubleOrNull(json['primary_disk_percent']),
      primaryDiskLabel: _stringOrNull(json['primary_disk_label']),
      primaryDiskFreeBytes: _intOrNull(json['primary_disk_free_bytes']),
      secondaryDiskPercent: _doubleOrNull(json['secondary_disk_percent']),
      secondaryDiskLabel: _stringOrNull(json['secondary_disk_label']),
      secondaryDiskFreeBytes: _intOrNull(json['secondary_disk_free_bytes']),
      raidHealth: _stringOrNull(json['raid_health']),
      diskHealth: _stringOrNull(json['disk_health']),
      networkRecvBytesPerSecond: _doubleOrNull(
        json['network_recv_bytes_per_second'],
      ),
      networkSendBytesPerSecond: _doubleOrNull(
        json['network_send_bytes_per_second'],
      ),
      networkBytesRecvTotal: _intOrNull(json['network_bytes_recv_total']),
      networkBytesSentTotal: _intOrNull(json['network_bytes_sent_total']),
      topNetworkSpeedMbps: _intOrNull(json['top_network_speed_mbps']),
      sourceNetworkBytesRecvTotal: _intOrNull(
        json['source_network_bytes_recv_total'],
      ),
      sourceNetworkBytesSentTotal: _intOrNull(
        json['source_network_bytes_sent_total'],
      ),
    );
  }

  factory ServerWidgetSnapshot.fromMonitoringData({
    required SummaryResponse summary,
    required SystemResponse system,
    required AppSettings settings,
    required DateTime updatedAt,
    GpuResponse? gpu,
    ServerWidgetSnapshot? previous,
  }) {
    final selectedDisk = _pickDisk(
      system.disks,
      settings.widgetStorageMountpoint,
    );
    final secondaryDisk = settings.widgetShowSecondaryStorage
        ? _pickDisk(system.disks, settings.widgetSecondaryStorageMountpoint)
        : null;
    final timestamp = updatedAt.toUtc();
    final receiveRate = _calculateThroughput(
      previousTotal: previous?.sourceNetworkBytesRecvTotal,
      currentTotal: system.network.bytesRecv,
      previousTimestamp: previous?.lastUpdatedUtc,
      currentTimestamp: timestamp,
    );
    final sendRate = _calculateThroughput(
      previousTotal: previous?.sourceNetworkBytesSentTotal,
      currentTotal: system.network.bytesSent,
      previousTimestamp: previous?.lastUpdatedUtc,
      currentTimestamp: timestamp,
    );
    final effectiveGpuAvailable =
        gpu?.available == true || summary.gpuAvailable;

    return ServerWidgetSnapshot(
      hostname: summary.hostname,
      serverReachable: true,
      lastUpdatedUtc: timestamp,
      isStale: false,
      cpuPercent: summary.cpuPercent,
      cpuTemperatureC: system.cpu.temperatureC,
      memoryPercent: summary.memoryPercent,
      gpuAvailable: effectiveGpuAvailable,
      gpuUtilizationPercent: effectiveGpuAvailable
          ? gpu?.utilizationPercent ?? summary.gpuUtilizationPercent
          : null,
      gpuTemperatureC: effectiveGpuAvailable
          ? gpu?.temperatureC ?? summary.gpuTempC
          : null,
      primaryDiskPercent: selectedDisk?.percent ?? system.disk.percent,
      primaryDiskLabel: _friendlyLabel(
        settings.widgetStorageLabel,
        fallback: 'Primary Storage',
      ),
      primaryDiskFreeBytes: selectedDisk?.free ?? system.disk.free,
      secondaryDiskPercent: secondaryDisk?.percent,
      secondaryDiskLabel: secondaryDisk == null
          ? null
          : _friendlyLabel(
              settings.widgetSecondaryStorageLabel,
              fallback: 'Secondary Storage',
            ),
      secondaryDiskFreeBytes: secondaryDisk?.free,
      raidHealth: _aggregateHealth(
        system.raidArrays.map((array) => array.health.status),
      ),
      diskHealth: _aggregateHealth([
        if (selectedDisk != null) selectedDisk.health.status,
        ...system.physicalDisks.map((disk) => disk.health.status),
      ]),
      networkRecvBytesPerSecond: receiveRate,
      networkSendBytesPerSecond: sendRate,
      networkBytesRecvTotal: system.network.bytesRecv,
      networkBytesSentTotal: system.network.bytesSent,
      topNetworkSpeedMbps: system.network.topSpeedMbps,
      sourceNetworkBytesRecvTotal: system.network.bytesRecv,
      sourceNetworkBytesSentTotal: system.network.bytesSent,
    );
  }

  factory ServerWidgetSnapshot.offlineFromPrevious({
    ServerWidgetSnapshot? previous,
    String fallbackHostname = 'Homelab Server',
  }) {
    if (previous != null) {
      return previous.copyWith(serverReachable: false, isStale: true);
    }
    return ServerWidgetSnapshot(
      hostname: fallbackHostname,
      serverReachable: false,
      lastUpdatedUtc: null,
      isStale: true,
      cpuPercent: null,
      cpuTemperatureC: null,
      memoryPercent: null,
      gpuAvailable: false,
      gpuUtilizationPercent: null,
      gpuTemperatureC: null,
      primaryDiskPercent: null,
      primaryDiskLabel: null,
      primaryDiskFreeBytes: null,
      secondaryDiskPercent: null,
      secondaryDiskLabel: null,
      secondaryDiskFreeBytes: null,
      raidHealth: null,
      diskHealth: null,
      networkRecvBytesPerSecond: null,
      networkSendBytesPerSecond: null,
      networkBytesRecvTotal: null,
      networkBytesSentTotal: null,
      topNetworkSpeedMbps: null,
      sourceNetworkBytesRecvTotal: null,
      sourceNetworkBytesSentTotal: null,
    );
  }

  final String hostname;
  final bool serverReachable;
  final DateTime? lastUpdatedUtc;
  final bool isStale;
  final double? cpuPercent;
  final double? cpuTemperatureC;
  final double? memoryPercent;
  final bool gpuAvailable;
  final double? gpuUtilizationPercent;
  final double? gpuTemperatureC;
  final double? primaryDiskPercent;
  final String? primaryDiskLabel;
  final int? primaryDiskFreeBytes;
  final double? secondaryDiskPercent;
  final String? secondaryDiskLabel;
  final int? secondaryDiskFreeBytes;
  final String? raidHealth;
  final String? diskHealth;
  final double? networkRecvBytesPerSecond;
  final double? networkSendBytesPerSecond;
  final int? networkBytesRecvTotal;
  final int? networkBytesSentTotal;
  final int? topNetworkSpeedMbps;
  final int? sourceNetworkBytesRecvTotal;
  final int? sourceNetworkBytesSentTotal;

  ServerWidgetSnapshot copyWith({
    String? hostname,
    bool? serverReachable,
    DateTime? lastUpdatedUtc,
    bool? isStale,
    double? cpuPercent,
    double? cpuTemperatureC,
    double? memoryPercent,
    bool? gpuAvailable,
    double? gpuUtilizationPercent,
    double? gpuTemperatureC,
    double? primaryDiskPercent,
    String? primaryDiskLabel,
    int? primaryDiskFreeBytes,
    double? secondaryDiskPercent,
    String? secondaryDiskLabel,
    int? secondaryDiskFreeBytes,
    String? raidHealth,
    String? diskHealth,
    double? networkRecvBytesPerSecond,
    double? networkSendBytesPerSecond,
    int? networkBytesRecvTotal,
    int? networkBytesSentTotal,
    int? topNetworkSpeedMbps,
    int? sourceNetworkBytesRecvTotal,
    int? sourceNetworkBytesSentTotal,
  }) {
    return ServerWidgetSnapshot(
      hostname: hostname ?? this.hostname,
      serverReachable: serverReachable ?? this.serverReachable,
      lastUpdatedUtc: lastUpdatedUtc ?? this.lastUpdatedUtc,
      isStale: isStale ?? this.isStale,
      cpuPercent: cpuPercent ?? this.cpuPercent,
      cpuTemperatureC: cpuTemperatureC ?? this.cpuTemperatureC,
      memoryPercent: memoryPercent ?? this.memoryPercent,
      gpuAvailable: gpuAvailable ?? this.gpuAvailable,
      gpuUtilizationPercent:
          gpuUtilizationPercent ?? this.gpuUtilizationPercent,
      gpuTemperatureC: gpuTemperatureC ?? this.gpuTemperatureC,
      primaryDiskPercent: primaryDiskPercent ?? this.primaryDiskPercent,
      primaryDiskLabel: primaryDiskLabel ?? this.primaryDiskLabel,
      primaryDiskFreeBytes: primaryDiskFreeBytes ?? this.primaryDiskFreeBytes,
      secondaryDiskPercent: secondaryDiskPercent ?? this.secondaryDiskPercent,
      secondaryDiskLabel: secondaryDiskLabel ?? this.secondaryDiskLabel,
      secondaryDiskFreeBytes:
          secondaryDiskFreeBytes ?? this.secondaryDiskFreeBytes,
      raidHealth: raidHealth ?? this.raidHealth,
      diskHealth: diskHealth ?? this.diskHealth,
      networkRecvBytesPerSecond:
          networkRecvBytesPerSecond ?? this.networkRecvBytesPerSecond,
      networkSendBytesPerSecond:
          networkSendBytesPerSecond ?? this.networkSendBytesPerSecond,
      networkBytesRecvTotal:
          networkBytesRecvTotal ?? this.networkBytesRecvTotal,
      networkBytesSentTotal:
          networkBytesSentTotal ?? this.networkBytesSentTotal,
      topNetworkSpeedMbps: topNetworkSpeedMbps ?? this.topNetworkSpeedMbps,
      sourceNetworkBytesRecvTotal:
          sourceNetworkBytesRecvTotal ?? this.sourceNetworkBytesRecvTotal,
      sourceNetworkBytesSentTotal:
          sourceNetworkBytesSentTotal ?? this.sourceNetworkBytesSentTotal,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'hostname': hostname,
      'server_reachable': serverReachable,
      'last_updated_utc': lastUpdatedUtc?.toIso8601String(),
      'last_updated_epoch_ms_utc': lastUpdatedUtc?.millisecondsSinceEpoch,
      'is_stale': isStale,
      'cpu_percent': cpuPercent,
      'cpu_temperature_c': cpuTemperatureC,
      'memory_percent': memoryPercent,
      'gpu_available': gpuAvailable,
      'gpu_utilization_percent': gpuUtilizationPercent,
      'gpu_temperature_c': gpuTemperatureC,
      'primary_disk_percent': primaryDiskPercent,
      'primary_disk_label': primaryDiskLabel,
      'primary_disk_free_bytes': primaryDiskFreeBytes,
      'secondary_disk_percent': secondaryDiskPercent,
      'secondary_disk_label': secondaryDiskLabel,
      'secondary_disk_free_bytes': secondaryDiskFreeBytes,
      'raid_health': raidHealth,
      'disk_health': diskHealth,
      'network_recv_bytes_per_second': networkRecvBytesPerSecond,
      'network_send_bytes_per_second': networkSendBytesPerSecond,
      'network_bytes_recv_total': networkBytesRecvTotal,
      'network_bytes_sent_total': networkBytesSentTotal,
      'top_network_speed_mbps': topNetworkSpeedMbps,
      'source_network_bytes_recv_total': sourceNetworkBytesRecvTotal,
      'source_network_bytes_sent_total': sourceNetworkBytesSentTotal,
    };
  }
}

DiskDeviceMetrics? _pickDisk(
  List<DiskDeviceMetrics> disks,
  String preferredMountpoint,
) {
  for (final disk in disks) {
    if (disk.mountpoint == preferredMountpoint) {
      return disk;
    }
  }
  return null;
}

double? _calculateThroughput({
  required int? previousTotal,
  required int currentTotal,
  required DateTime? previousTimestamp,
  required DateTime currentTimestamp,
}) {
  if (previousTotal == null || previousTimestamp == null) {
    return null;
  }
  final elapsedMs = currentTimestamp
      .difference(previousTimestamp)
      .inMilliseconds;
  if (elapsedMs <= 0 || currentTotal < previousTotal) {
    return null;
  }
  return (currentTotal - previousTotal) / (elapsedMs / 1000);
}

String? _aggregateHealth(Iterable<String> statuses) {
  var worstScore = -1;
  String? worstStatus;
  for (final status in statuses) {
    final score = switch (status.toLowerCase()) {
      'critical' => 3,
      'warning' => 2,
      'healthy' => 1,
      _ => 0,
    };
    if (score > worstScore) {
      worstScore = score;
      worstStatus = status;
    }
  }
  return worstStatus;
}

String _friendlyLabel(String value, {required String fallback}) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? fallback : trimmed;
}

bool _bool(Object? value) {
  if (value is bool) {
    return value;
  }
  if (value is String) {
    return value.toLowerCase() == 'true';
  }
  return false;
}

DateTime? _date(Object? value) {
  final raw = value?.toString();
  if (raw == null || raw.isEmpty) {
    return null;
  }
  return DateTime.tryParse(raw);
}

double? _doubleOrNull(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value);
  }
  return null;
}

int? _intOrNull(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}

String _string(Object? value, {required String fallback}) {
  return _stringOrNull(value) ?? fallback;
}

String? _stringOrNull(Object? value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) {
    return null;
  }
  return text;
}
