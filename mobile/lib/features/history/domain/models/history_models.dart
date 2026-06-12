enum HistoryRangeValue {
  oneHour('1h', '1h'),
  twentyFourHours('24h', '24h'),
  sevenDays('7d', '7d'),
  thirtyDays('30d', '30d');

  const HistoryRangeValue(this.apiKey, this.label);

  final String apiKey;
  final String label;

  static HistoryRangeValue fromApiKey(String value) {
    return HistoryRangeValue.values.firstWhere(
      (item) => item.apiKey == value,
      orElse: () => HistoryRangeValue.twentyFourHours,
    );
  }
}

class HistoryRangesResponseModel {
  const HistoryRangesResponseModel({
    required this.defaultRange,
    required this.maxPointsCap,
    required this.ranges,
  });

  factory HistoryRangesResponseModel.fromJson(Map<String, dynamic> json) {
    return HistoryRangesResponseModel(
      defaultRange: HistoryRangeValue.fromApiKey(
        json['default_range'] as String? ?? '24h',
      ),
      maxPointsCap: json['max_points_cap'] as int? ?? 360,
      ranges: [
        for (final item in (json['ranges'] as List<dynamic>? ?? const []))
          HistoryRangeDescriptor.fromJson(item as Map<String, dynamic>),
      ],
    );
  }

  final HistoryRangeValue defaultRange;
  final int maxPointsCap;
  final List<HistoryRangeDescriptor> ranges;
}

class HistoryRangeDescriptor {
  const HistoryRangeDescriptor({
    required this.range,
    required this.label,
    required this.durationSeconds,
  });

  factory HistoryRangeDescriptor.fromJson(Map<String, dynamic> json) {
    return HistoryRangeDescriptor(
      range: HistoryRangeValue.fromApiKey(json['key'] as String? ?? '24h'),
      label: json['label'] as String? ?? 'Unknown',
      durationSeconds: json['duration_seconds'] as int? ?? 0,
    );
  }

  final HistoryRangeValue range;
  final String label;
  final int durationSeconds;
}

class HistoryInventory {
  const HistoryInventory({
    required this.mountpoints,
    required this.diskDevices,
    required this.raidArrays,
  });

  final List<String> mountpoints;
  final List<String> diskDevices;
  final List<String> raidArrays;
}

class CachedHistoryData<T> {
  const CachedHistoryData({
    required this.data,
    required this.fromCache,
    required this.cachedAt,
  });

  final T data;
  final bool fromCache;
  final DateTime? cachedAt;
}

class HistoryOverviewResponseModel {
  const HistoryOverviewResponseModel({
    required this.range,
    required this.from,
    required this.to,
    required this.resolutionSeconds,
    required this.maxPoints,
    required this.points,
  });

  factory HistoryOverviewResponseModel.fromJson(Map<String, dynamic> json) {
    return HistoryOverviewResponseModel(
      range: HistoryRangeValue.fromApiKey(json['range'] as String? ?? '24h'),
      from: _parseDateTime(json['from']),
      to: _parseDateTime(json['to']),
      resolutionSeconds: json['resolution_seconds'] as int? ?? 0,
      maxPoints: json['max_points'] as int? ?? 0,
      points: [
        for (final item in (json['points'] as List<dynamic>? ?? const []))
          HistoryOverviewPoint.fromJson(item as Map<String, dynamic>),
      ],
    );
  }

  final HistoryRangeValue range;
  final DateTime? from;
  final DateTime? to;
  final int resolutionSeconds;
  final int maxPoints;
  final List<HistoryOverviewPoint> points;
}

class HistoryOverviewPoint {
  const HistoryOverviewPoint({
    required this.timestamp,
    required this.cpuPercentAvg,
    required this.cpuPercentMax,
    required this.cpuTemperatureCAvg,
    required this.cpuTemperatureCMax,
    required this.memoryPercentAvg,
    required this.swapPercentAvg,
    required this.gpuUtilizationPercentAvg,
    required this.gpuTemperatureCAvg,
    required this.gpuMemoryUsedMbAvg,
    required this.gpuPowerUsageWAvg,
    required this.networkRecvBytesPerSecondAvg,
    required this.networkSendBytesPerSecondAvg,
    required this.runningContainersAvg,
  });

  factory HistoryOverviewPoint.fromJson(Map<String, dynamic> json) {
    return HistoryOverviewPoint(
      timestamp: _parseDateTime(json['timestamp']),
      cpuPercentAvg: _toDouble(json['cpu_percent_avg']),
      cpuPercentMax: _toDouble(json['cpu_percent_max']),
      cpuTemperatureCAvg: _toDouble(json['cpu_temperature_c_avg']),
      cpuTemperatureCMax: _toDouble(json['cpu_temperature_c_max']),
      memoryPercentAvg: _toDouble(json['memory_percent_avg']),
      swapPercentAvg: _toDouble(json['swap_percent_avg']),
      gpuUtilizationPercentAvg: _toDouble(json['gpu_utilization_percent_avg']),
      gpuTemperatureCAvg: _toDouble(json['gpu_temperature_c_avg']),
      gpuMemoryUsedMbAvg: _toDouble(json['gpu_memory_used_mb_avg']),
      gpuPowerUsageWAvg: _toDouble(json['gpu_power_usage_w_avg']),
      networkRecvBytesPerSecondAvg: _toDouble(
        json['network_recv_bytes_per_second_avg'],
      ),
      networkSendBytesPerSecondAvg: _toDouble(
        json['network_send_bytes_per_second_avg'],
      ),
      runningContainersAvg: _toDouble(json['running_containers_avg']),
    );
  }

  final DateTime? timestamp;
  final double? cpuPercentAvg;
  final double? cpuPercentMax;
  final double? cpuTemperatureCAvg;
  final double? cpuTemperatureCMax;
  final double? memoryPercentAvg;
  final double? swapPercentAvg;
  final double? gpuUtilizationPercentAvg;
  final double? gpuTemperatureCAvg;
  final double? gpuMemoryUsedMbAvg;
  final double? gpuPowerUsageWAvg;
  final double? networkRecvBytesPerSecondAvg;
  final double? networkSendBytesPerSecondAvg;
  final double? runningContainersAvg;
}

class StorageHistoryResponseModel {
  const StorageHistoryResponseModel({
    required this.range,
    required this.mountpoint,
    required this.from,
    required this.to,
    required this.resolutionSeconds,
    required this.maxPoints,
    required this.points,
  });

  factory StorageHistoryResponseModel.fromJson(Map<String, dynamic> json) {
    return StorageHistoryResponseModel(
      range: HistoryRangeValue.fromApiKey(json['range'] as String? ?? '24h'),
      mountpoint: json['mountpoint'] as String? ?? '/',
      from: _parseDateTime(json['from']),
      to: _parseDateTime(json['to']),
      resolutionSeconds: json['resolution_seconds'] as int? ?? 0,
      maxPoints: json['max_points'] as int? ?? 0,
      points: [
        for (final item in (json['points'] as List<dynamic>? ?? const []))
          StorageHistoryPoint.fromJson(item as Map<String, dynamic>),
      ],
    );
  }

  final HistoryRangeValue range;
  final String mountpoint;
  final DateTime? from;
  final DateTime? to;
  final int resolutionSeconds;
  final int maxPoints;
  final List<StorageHistoryPoint> points;
}

class StorageHistoryPoint {
  const StorageHistoryPoint({
    required this.timestamp,
    required this.usedBytesAvg,
    required this.freeBytesAvg,
    required this.totalBytesAvg,
    required this.percentAvg,
    required this.percentMax,
    required this.readOnlyAny,
    required this.availableAny,
    required this.healthStatus,
  });

  factory StorageHistoryPoint.fromJson(Map<String, dynamic> json) {
    return StorageHistoryPoint(
      timestamp: _parseDateTime(json['timestamp']),
      usedBytesAvg: _toDouble(json['used_bytes_avg']),
      freeBytesAvg: _toDouble(json['free_bytes_avg']),
      totalBytesAvg: _toDouble(json['total_bytes_avg']),
      percentAvg: _toDouble(json['percent_avg']),
      percentMax: _toDouble(json['percent_max']),
      readOnlyAny: json['read_only_any'] as bool? ?? false,
      availableAny: json['available_any'] as bool? ?? false,
      healthStatus: json['health_status'] as String? ?? 'unknown',
    );
  }

  final DateTime? timestamp;
  final double? usedBytesAvg;
  final double? freeBytesAvg;
  final double? totalBytesAvg;
  final double? percentAvg;
  final double? percentMax;
  final bool readOnlyAny;
  final bool availableAny;
  final String healthStatus;
}

class DiskHistoryResponseModel {
  const DiskHistoryResponseModel({
    required this.range,
    required this.device,
    required this.from,
    required this.to,
    required this.resolutionSeconds,
    required this.maxPoints,
    required this.points,
  });

  factory DiskHistoryResponseModel.fromJson(Map<String, dynamic> json) {
    return DiskHistoryResponseModel(
      range: HistoryRangeValue.fromApiKey(json['range'] as String? ?? '24h'),
      device: json['device'] as String? ?? 'unknown',
      from: _parseDateTime(json['from']),
      to: _parseDateTime(json['to']),
      resolutionSeconds: json['resolution_seconds'] as int? ?? 0,
      maxPoints: json['max_points'] as int? ?? 0,
      points: [
        for (final item in (json['points'] as List<dynamic>? ?? const []))
          DiskHistoryPoint.fromJson(item as Map<String, dynamic>),
      ],
    );
  }

  final HistoryRangeValue range;
  final String device;
  final DateTime? from;
  final DateTime? to;
  final int resolutionSeconds;
  final int maxPoints;
  final List<DiskHistoryPoint> points;
}

class DiskHistoryPoint {
  const DiskHistoryPoint({
    required this.timestamp,
    required this.temperatureCAvg,
    required this.healthStatus,
    required this.kernelState,
  });

  factory DiskHistoryPoint.fromJson(Map<String, dynamic> json) {
    return DiskHistoryPoint(
      timestamp: _parseDateTime(json['timestamp']),
      temperatureCAvg: _toDouble(json['temperature_c_avg']),
      healthStatus: json['health_status'] as String? ?? 'unknown',
      kernelState: json['kernel_state'] as String?,
    );
  }

  final DateTime? timestamp;
  final double? temperatureCAvg;
  final String healthStatus;
  final String? kernelState;
}

class RaidHistoryResponseModel {
  const RaidHistoryResponseModel({
    required this.range,
    required this.arrayName,
    required this.from,
    required this.to,
    required this.resolutionSeconds,
    required this.maxPoints,
    required this.points,
  });

  factory RaidHistoryResponseModel.fromJson(Map<String, dynamic> json) {
    return RaidHistoryResponseModel(
      range: HistoryRangeValue.fromApiKey(json['range'] as String? ?? '24h'),
      arrayName: json['array_name'] as String? ?? 'unknown',
      from: _parseDateTime(json['from']),
      to: _parseDateTime(json['to']),
      resolutionSeconds: json['resolution_seconds'] as int? ?? 0,
      maxPoints: json['max_points'] as int? ?? 0,
      points: [
        for (final item in (json['points'] as List<dynamic>? ?? const []))
          RaidHistoryPoint.fromJson(item as Map<String, dynamic>),
      ],
    );
  }

  final HistoryRangeValue range;
  final String arrayName;
  final DateTime? from;
  final DateTime? to;
  final int resolutionSeconds;
  final int maxPoints;
  final List<RaidHistoryPoint> points;
}

class RaidHistoryPoint {
  const RaidHistoryPoint({
    required this.timestamp,
    required this.activeDevicesAvg,
    required this.degradedDevicesAvg,
    required this.state,
    required this.syncAction,
    required this.healthStatus,
  });

  factory RaidHistoryPoint.fromJson(Map<String, dynamic> json) {
    return RaidHistoryPoint(
      timestamp: _parseDateTime(json['timestamp']),
      activeDevicesAvg: _toDouble(json['active_devices_avg']),
      degradedDevicesAvg: _toDouble(json['degraded_devices_avg']),
      state: json['state'] as String?,
      syncAction: json['sync_action'] as String?,
      healthStatus: json['health_status'] as String? ?? 'unknown',
    );
  }

  final DateTime? timestamp;
  final double? activeDevicesAvg;
  final double? degradedDevicesAvg;
  final String? state;
  final String? syncAction;
  final String healthStatus;
}

class HistoryChartPoint {
  const HistoryChartPoint({required this.timestamp, required this.value});

  final DateTime? timestamp;
  final double? value;
}

DateTime? _parseDateTime(Object? value) {
  final text = value as String?;
  if (text == null || text.isEmpty) {
    return null;
  }
  return DateTime.tryParse(text);
}

double? _toDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  return null;
}
