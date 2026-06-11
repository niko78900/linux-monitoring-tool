import '../../../../core/widgets/status_tone.dart';

class HealthResponse {
  const HealthResponse({
    required this.status,
    required this.appName,
    required this.version,
    required this.timestamp,
  });

  factory HealthResponse.fromJson(Map<String, dynamic> json) {
    return HealthResponse(
      status: _string(json['status'], fallback: 'unknown'),
      appName: _string(json['app_name'], fallback: 'unknown'),
      version: _string(json['version'], fallback: 'unknown'),
      timestamp: _date(json['timestamp']),
    );
  }

  final String status;
  final String appName;
  final String version;
  final DateTime? timestamp;
}

class SummaryResponse {
  const SummaryResponse({
    required this.hostname,
    required this.uptimeHuman,
    required this.cpuPercent,
    required this.memoryPercent,
    required this.diskPercent,
    required this.gpuAvailable,
    required this.gpuUtilizationPercent,
    required this.gpuTempC,
    required this.dockerAvailable,
    required this.runningContainers,
  });

  factory SummaryResponse.fromJson(Map<String, dynamic> json) {
    return SummaryResponse(
      hostname: _string(json['hostname'], fallback: 'unknown'),
      uptimeHuman: _string(json['uptime_human'], fallback: 'N/A'),
      cpuPercent: _double(json['cpu_percent']),
      memoryPercent: _double(json['memory_percent']),
      diskPercent: _double(json['disk_percent']),
      gpuAvailable: _bool(json['gpu_available']),
      gpuUtilizationPercent: _nullableDouble(json['gpu_utilization_percent']),
      gpuTempC: _nullableDouble(json['gpu_temp_c']),
      dockerAvailable: _bool(json['docker_available']),
      runningContainers: _int(json['running_containers']),
    );
  }

  final String hostname;
  final String uptimeHuman;
  final double cpuPercent;
  final double memoryPercent;
  final double diskPercent;
  final bool gpuAvailable;
  final double? gpuUtilizationPercent;
  final double? gpuTempC;
  final bool dockerAvailable;
  final int runningContainers;
}

class GpuResponse {
  const GpuResponse({
    required this.available,
    required this.reason,
    required this.name,
    required this.temperatureC,
    required this.utilizationPercent,
    required this.memoryTotalMb,
    required this.memoryUsedMb,
    required this.memoryFreeMb,
    required this.powerUsageW,
    required this.fanSpeedPercent,
    required this.driverVersion,
  });

  factory GpuResponse.fromJson(Map<String, dynamic> json) {
    return GpuResponse(
      available: _bool(json['available']),
      reason: _nullableString(json['reason']),
      name: _nullableString(json['name']),
      temperatureC: _nullableDouble(json['temperature_c']),
      utilizationPercent: _nullableDouble(json['utilization_percent']),
      memoryTotalMb: _nullableInt(json['memory_total_mb']),
      memoryUsedMb: _nullableInt(json['memory_used_mb']),
      memoryFreeMb: _nullableInt(json['memory_free_mb']),
      powerUsageW: _nullableDouble(json['power_usage_w']),
      fanSpeedPercent: _nullableInt(json['fan_speed_percent']),
      driverVersion: _nullableString(json['driver_version']),
    );
  }

  final bool available;
  final String? reason;
  final String? name;
  final double? temperatureC;
  final double? utilizationPercent;
  final int? memoryTotalMb;
  final int? memoryUsedMb;
  final int? memoryFreeMb;
  final double? powerUsageW;
  final int? fanSpeedPercent;
  final String? driverVersion;

  double? get memoryUsedPercent {
    final used = memoryUsedMb;
    final total = memoryTotalMb;
    if (used == null || total == null || total <= 0) {
      return null;
    }
    return used / total * 100;
  }
}

class DockerResponse {
  const DockerResponse({
    required this.dockerAvailable,
    required this.reason,
    required this.containerCount,
    required this.containers,
  });

  factory DockerResponse.fromJson(Map<String, dynamic> json) {
    return DockerResponse(
      dockerAvailable: _bool(json['docker_available']),
      reason: _nullableString(json['reason']),
      containerCount: _int(json['container_count']),
      containers: _list(json['containers'], DockerContainerInfo.fromJson),
    );
  }

  final bool dockerAvailable;
  final String? reason;
  final int containerCount;
  final List<DockerContainerInfo> containers;

  int get runningCount =>
      containers.where((item) => item.state.toLowerCase() == 'running').length;
}

class DockerContainerInfo {
  const DockerContainerInfo({
    required this.id,
    required this.name,
    required this.image,
    required this.state,
    required this.status,
    required this.ports,
    required this.created,
    required this.runningFor,
  });

  factory DockerContainerInfo.fromJson(Map<String, dynamic> json) {
    final rawPorts = json['ports'];
    final ports = <String, List<String>>{};
    if (rawPorts is Map) {
      for (final entry in rawPorts.entries) {
        final value = entry.value;
        if (value is List) {
          ports[entry.key.toString()] = value
              .map((item) => item.toString())
              .toList();
        } else if (value != null) {
          ports[entry.key.toString()] = [value.toString()];
        }
      }
    }
    return DockerContainerInfo(
      id: _string(json['id'], fallback: 'unknown'),
      name: _string(json['name'], fallback: 'unknown'),
      image: _string(json['image'], fallback: 'unknown'),
      state: _string(json['state'], fallback: 'unknown'),
      status: _string(json['status'], fallback: 'unknown'),
      ports: ports,
      created: _nullableString(json['created']),
      runningFor: _nullableString(json['running_for']),
    );
  }

  final String id;
  final String name;
  final String image;
  final String state;
  final String status;
  final Map<String, List<String>> ports;
  final String? created;
  final String? runningFor;
}

class SystemResponse {
  const SystemResponse({
    required this.hostname,
    required this.os,
    required this.kernelVersion,
    required this.specs,
    required this.chassisTemperatureC,
    required this.uptimeSeconds,
    required this.uptimeHuman,
    required this.bootTime,
    required this.cpu,
    required this.memory,
    required this.swap,
    required this.disk,
    required this.disks,
    required this.raidArrays,
    required this.physicalDisks,
    required this.network,
  });

  factory SystemResponse.fromJson(Map<String, dynamic> json) {
    return SystemResponse(
      hostname: _string(json['hostname'], fallback: 'unknown'),
      os: PlatformInfo.fromJson(_map(json['os'])),
      kernelVersion: _string(json['kernel_version'], fallback: 'unknown'),
      specs: SystemSpecs.fromJson(_map(json['specs'])),
      chassisTemperatureC: _nullableDouble(json['chassis_temperature_c']),
      uptimeSeconds: _int(json['uptime_seconds']),
      uptimeHuman: _string(json['uptime_human'], fallback: 'N/A'),
      bootTime: _date(json['boot_time']),
      cpu: CpuMetrics.fromJson(_map(json['cpu'])),
      memory: MemoryMetrics.fromJson(_map(json['memory'])),
      swap: SwapMetrics.fromJson(_map(json['swap'])),
      disk: DiskMetrics.fromJson(_map(json['disk'])),
      disks: _list(json['disks'], DiskDeviceMetrics.fromJson),
      raidArrays: _list(json['raid_arrays'], RaidArrayMetrics.fromJson),
      physicalDisks: _list(
        json['physical_disks'],
        PhysicalDiskMetrics.fromJson,
      ),
      network: NetworkMetrics.fromJson(_map(json['network'])),
    );
  }

  final String hostname;
  final PlatformInfo os;
  final String kernelVersion;
  final SystemSpecs specs;
  final double? chassisTemperatureC;
  final int uptimeSeconds;
  final String uptimeHuman;
  final DateTime? bootTime;
  final CpuMetrics cpu;
  final MemoryMetrics memory;
  final SwapMetrics swap;
  final DiskMetrics disk;
  final List<DiskDeviceMetrics> disks;
  final List<RaidArrayMetrics> raidArrays;
  final List<PhysicalDiskMetrics> physicalDisks;
  final NetworkMetrics network;
}

class PlatformInfo {
  const PlatformInfo({
    required this.system,
    required this.release,
    required this.version,
    required this.machine,
    required this.platform,
  });

  factory PlatformInfo.fromJson(Map<String, dynamic> json) {
    return PlatformInfo(
      system: _string(json['system'], fallback: 'unknown'),
      release: _string(json['release'], fallback: 'unknown'),
      version: _string(json['version'], fallback: 'unknown'),
      machine: _string(json['machine'], fallback: 'unknown'),
      platform: _string(json['platform'], fallback: 'unknown'),
    );
  }

  final String system;
  final String release;
  final String version;
  final String machine;
  final String platform;
}

class LoadAverage {
  const LoadAverage({
    required this.oneMin,
    required this.fiveMin,
    required this.fifteenMin,
  });

  factory LoadAverage.fromJson(Map<String, dynamic> json) {
    return LoadAverage(
      oneMin: _double(json['one_min']),
      fiveMin: _double(json['five_min']),
      fifteenMin: _double(json['fifteen_min']),
    );
  }

  final double oneMin;
  final double fiveMin;
  final double fifteenMin;
}

class CpuMetrics {
  const CpuMetrics({
    required this.usagePercent,
    required this.physicalCores,
    required this.logicalCores,
    required this.loadAverage,
    required this.temperatureC,
  });

  factory CpuMetrics.fromJson(Map<String, dynamic> json) {
    final load = json['load_average'];
    return CpuMetrics(
      usagePercent: _double(json['usage_percent']),
      physicalCores: _int(json['physical_cores']),
      logicalCores: _int(json['logical_cores']),
      loadAverage: load is Map ? LoadAverage.fromJson(_map(load)) : null,
      temperatureC: _nullableDouble(json['temperature_c']),
    );
  }

  final double usagePercent;
  final int physicalCores;
  final int logicalCores;
  final LoadAverage? loadAverage;
  final double? temperatureC;
}

class CpuSpecs {
  const CpuSpecs({
    required this.modelName,
    required this.vendor,
    required this.architecture,
    required this.physicalCores,
    required this.logicalCores,
    required this.minFrequencyMhz,
    required this.maxFrequencyMhz,
    required this.capabilities,
  });

  factory CpuSpecs.fromJson(Map<String, dynamic> json) {
    return CpuSpecs(
      modelName: _string(json['model_name'], fallback: 'unknown'),
      vendor: _nullableString(json['vendor']),
      architecture: _string(json['architecture'], fallback: 'unknown'),
      physicalCores: _int(json['physical_cores']),
      logicalCores: _int(json['logical_cores']),
      minFrequencyMhz: _nullableDouble(json['min_frequency_mhz']),
      maxFrequencyMhz: _nullableDouble(json['max_frequency_mhz']),
      capabilities: _stringList(json['capabilities']),
    );
  }

  final String modelName;
  final String? vendor;
  final String architecture;
  final int physicalCores;
  final int logicalCores;
  final double? minFrequencyMhz;
  final double? maxFrequencyMhz;
  final List<String> capabilities;
}

class MemoryModuleSpecs {
  const MemoryModuleSpecs({
    required this.slot,
    required this.manufacturer,
    required this.partNumber,
    required this.memoryType,
    required this.sizeBytes,
    required this.speedMhz,
  });

  factory MemoryModuleSpecs.fromJson(Map<String, dynamic> json) {
    return MemoryModuleSpecs(
      slot: _nullableString(json['slot']),
      manufacturer: _nullableString(json['manufacturer']),
      partNumber: _nullableString(json['part_number']),
      memoryType: _nullableString(json['memory_type']),
      sizeBytes: _int(json['size_bytes']),
      speedMhz: _nullableInt(json['speed_mhz']),
    );
  }

  final String? slot;
  final String? manufacturer;
  final String? partNumber;
  final String? memoryType;
  final int sizeBytes;
  final int? speedMhz;
}

class MemorySpecs {
  const MemorySpecs({
    required this.totalBytes,
    required this.speedMhz,
    required this.memoryType,
    required this.manufacturers,
    required this.modules,
  });

  factory MemorySpecs.fromJson(Map<String, dynamic> json) {
    return MemorySpecs(
      totalBytes: _int(json['total_bytes']),
      speedMhz: _nullableInt(json['speed_mhz']),
      memoryType: _nullableString(json['memory_type']),
      manufacturers: _stringList(json['manufacturers']),
      modules: _list(json['modules'], MemoryModuleSpecs.fromJson),
    );
  }

  final int totalBytes;
  final int? speedMhz;
  final String? memoryType;
  final List<String> manufacturers;
  final List<MemoryModuleSpecs> modules;
}

class MotherboardSpecs {
  const MotherboardSpecs({
    required this.vendor,
    required this.model,
    required this.version,
    required this.chipset,
  });

  factory MotherboardSpecs.fromJson(Map<String, dynamic> json) {
    return MotherboardSpecs(
      vendor: _nullableString(json['vendor']),
      model: _nullableString(json['model']),
      version: _nullableString(json['version']),
      chipset: _nullableString(json['chipset']),
    );
  }

  final String? vendor;
  final String? model;
  final String? version;
  final String? chipset;
}

class GpuSpecs {
  const GpuSpecs({
    required this.available,
    required this.reason,
    required this.brand,
    required this.model,
    required this.driverVersion,
    required this.vramTotalMb,
    required this.cudaComputeCapability,
    required this.capabilities,
  });

  factory GpuSpecs.fromJson(Map<String, dynamic> json) {
    return GpuSpecs(
      available: _bool(json['available']),
      reason: _nullableString(json['reason']),
      brand: _nullableString(json['brand']),
      model: _nullableString(json['model']),
      driverVersion: _nullableString(json['driver_version']),
      vramTotalMb: _nullableInt(json['vram_total_mb']),
      cudaComputeCapability: _nullableString(json['cuda_compute_capability']),
      capabilities: _stringList(json['capabilities']),
    );
  }

  final bool available;
  final String? reason;
  final String? brand;
  final String? model;
  final String? driverVersion;
  final int? vramTotalMb;
  final String? cudaComputeCapability;
  final List<String> capabilities;
}

class SystemSpecs {
  const SystemSpecs({
    required this.cpu,
    required this.memoryTotalBytes,
    required this.swapTotalBytes,
    required this.memory,
    required this.motherboard,
    required this.gpu,
  });

  factory SystemSpecs.fromJson(Map<String, dynamic> json) {
    return SystemSpecs(
      cpu: CpuSpecs.fromJson(_map(json['cpu'])),
      memoryTotalBytes: _int(json['memory_total_bytes']),
      swapTotalBytes: _int(json['swap_total_bytes']),
      memory: MemorySpecs.fromJson(_map(json['memory'])),
      motherboard: MotherboardSpecs.fromJson(_map(json['motherboard'])),
      gpu: GpuSpecs.fromJson(_map(json['gpu'])),
    );
  }

  final CpuSpecs cpu;
  final int memoryTotalBytes;
  final int swapTotalBytes;
  final MemorySpecs memory;
  final MotherboardSpecs motherboard;
  final GpuSpecs gpu;
}

class MemoryMetrics {
  const MemoryMetrics({
    required this.total,
    required this.available,
    required this.used,
    required this.percent,
  });

  factory MemoryMetrics.fromJson(Map<String, dynamic> json) {
    return MemoryMetrics(
      total: _int(json['total']),
      available: _int(json['available']),
      used: _int(json['used']),
      percent: _double(json['percent']),
    );
  }

  final int total;
  final int available;
  final int used;
  final double percent;
}

class SwapMetrics {
  const SwapMetrics({
    required this.total,
    required this.used,
    required this.percent,
  });

  factory SwapMetrics.fromJson(Map<String, dynamic> json) {
    return SwapMetrics(
      total: _int(json['total']),
      used: _int(json['used']),
      percent: _double(json['percent']),
    );
  }

  final int total;
  final int used;
  final double percent;
}

class DiskMetrics {
  const DiskMetrics({
    required this.total,
    required this.used,
    required this.free,
    required this.percent,
    required this.mountpoint,
  });

  factory DiskMetrics.fromJson(Map<String, dynamic> json) {
    return DiskMetrics(
      total: _int(json['total']),
      used: _int(json['used']),
      free: _int(json['free']),
      percent: _double(json['percent']),
      mountpoint: _string(json['mountpoint'], fallback: '/'),
    );
  }

  final int total;
  final int used;
  final int free;
  final double percent;
  final String mountpoint;
}

class HealthInfo {
  const HealthInfo({required this.status, required this.reason});

  factory HealthInfo.fromJson(Map<String, dynamic> json) {
    return HealthInfo(
      status: _healthStatus(json['status']),
      reason: _string(json['reason'], fallback: 'No details available.'),
    );
  }

  final String status;
  final String reason;

  StatusTone get tone {
    return switch (status) {
      'healthy' => StatusTone.healthy,
      'warning' => StatusTone.warning,
      'critical' => StatusTone.critical,
      'unknown' => StatusTone.unknown,
      _ => StatusTone.neutral,
    };
  }
}

class DiskDeviceMetrics {
  const DiskDeviceMetrics({
    required this.device,
    required this.mountpoint,
    required this.fstype,
    required this.total,
    required this.used,
    required this.free,
    required this.percent,
    required this.readOnly,
    required this.available,
    required this.raidArray,
    required this.raidLevel,
    required this.health,
  });

  factory DiskDeviceMetrics.fromJson(Map<String, dynamic> json) {
    return DiskDeviceMetrics(
      device: _string(json['device'], fallback: 'unknown'),
      mountpoint: _string(json['mountpoint'], fallback: 'unknown'),
      fstype: _string(json['fstype'], fallback: 'unknown'),
      total: _int(json['total']),
      used: _int(json['used']),
      free: _int(json['free']),
      percent: _double(json['percent']),
      readOnly: _bool(json['read_only']),
      available: _bool(json['available'], fallback: true),
      raidArray: _nullableString(json['raid_array']),
      raidLevel: _nullableString(json['raid_level']),
      health: HealthInfo.fromJson(_map(json['health'])),
    );
  }

  final String device;
  final String mountpoint;
  final String fstype;
  final int total;
  final int used;
  final int free;
  final double percent;
  final bool readOnly;
  final bool available;
  final String? raidArray;
  final String? raidLevel;
  final HealthInfo health;
}

class RaidArrayMetrics {
  const RaidArrayMetrics({
    required this.name,
    required this.device,
    required this.level,
    required this.state,
    required this.raidDisks,
    required this.activeDevices,
    required this.degradedDevices,
    required this.syncAction,
    required this.members,
    required this.health,
  });

  factory RaidArrayMetrics.fromJson(Map<String, dynamic> json) {
    return RaidArrayMetrics(
      name: _string(json['name'], fallback: 'unknown'),
      device: _string(json['device'], fallback: 'unknown'),
      level: _string(json['level'], fallback: 'unknown'),
      state: _string(json['state'], fallback: 'unknown'),
      raidDisks: _int(json['raid_disks']),
      activeDevices: _int(json['active_devices']),
      degradedDevices: _int(json['degraded_devices']),
      syncAction: _nullableString(json['sync_action']),
      members: _stringList(json['members']),
      health: HealthInfo.fromJson(_map(json['health'])),
    );
  }

  final String name;
  final String device;
  final String level;
  final String state;
  final int raidDisks;
  final int activeDevices;
  final int degradedDevices;
  final String? syncAction;
  final List<String> members;
  final HealthInfo health;
}

class PhysicalDiskMetrics {
  const PhysicalDiskMetrics({
    required this.name,
    required this.device,
    required this.model,
    required this.vendor,
    required this.serial,
    required this.sizeBytes,
    required this.temperatureC,
    required this.rotational,
    required this.removable,
    required this.state,
    required this.mountedPartitions,
    required this.raidArrays,
    required this.health,
  });

  factory PhysicalDiskMetrics.fromJson(Map<String, dynamic> json) {
    return PhysicalDiskMetrics(
      name: _string(json['name'], fallback: 'unknown'),
      device: _string(json['device'], fallback: 'unknown'),
      model: _nullableString(json['model']),
      vendor: _nullableString(json['vendor']),
      serial: _nullableString(json['serial']),
      sizeBytes: _int(json['size_bytes']),
      temperatureC: _nullableDouble(json['temperature_c']),
      rotational: _nullableBool(json['rotational']),
      removable: _bool(json['removable']),
      state: _nullableString(json['state']),
      mountedPartitions: _stringList(json['mounted_partitions']),
      raidArrays: _stringList(json['raid_arrays']),
      health: HealthInfo.fromJson(_map(json['health'])),
    );
  }

  final String name;
  final String device;
  final String? model;
  final String? vendor;
  final String? serial;
  final int sizeBytes;
  final double? temperatureC;
  final bool? rotational;
  final bool removable;
  final String? state;
  final List<String> mountedPartitions;
  final List<String> raidArrays;
  final HealthInfo health;

  String get diskType {
    if (rotational == true) {
      return 'HDD';
    }
    if (rotational == false) {
      return 'SSD';
    }
    return 'N/A';
  }
}

class NetworkMetrics {
  const NetworkMetrics({
    required this.bytesSent,
    required this.bytesRecv,
    required this.packetsSent,
    required this.packetsRecv,
    required this.topSpeedMbps,
  });

  factory NetworkMetrics.fromJson(Map<String, dynamic> json) {
    return NetworkMetrics(
      bytesSent: _int(json['bytes_sent']),
      bytesRecv: _int(json['bytes_recv']),
      packetsSent: _int(json['packets_sent']),
      packetsRecv: _int(json['packets_recv']),
      topSpeedMbps: _nullableInt(json['top_speed_mbps']),
    );
  }

  final int bytesSent;
  final int bytesRecv;
  final int packetsSent;
  final int packetsRecv;
  final int? topSpeedMbps;
}

String _string(Object? value, {required String fallback}) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? fallback : text;
}

String? _nullableString(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

double _double(Object? value) => _nullableDouble(value) ?? 0;

double? _nullableDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value);
  }
  return null;
}

int _int(Object? value) => _nullableInt(value) ?? 0;

int? _nullableInt(Object? value) {
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

bool _bool(Object? value, {bool fallback = false}) {
  return _nullableBool(value) ?? fallback;
}

bool? _nullableBool(Object? value) {
  if (value is bool) {
    return value;
  }
  if (value is String) {
    return switch (value.trim().toLowerCase()) {
      '1' || 'true' || 'yes' || 'on' => true,
      '0' || 'false' || 'no' || 'off' => false,
      _ => null,
    };
  }
  return null;
}

DateTime? _date(Object? value) {
  final text = _nullableString(value);
  if (text == null) {
    return null;
  }
  return DateTime.tryParse(text);
}

Map<String, dynamic> _map(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return const {};
}

List<String> _stringList(Object? value) {
  if (value is List) {
    return value.map((item) => item.toString()).toList();
  }
  return const [];
}

List<T> _list<T>(Object? value, T Function(Map<String, dynamic>) builder) {
  if (value is! List) {
    return const [];
  }
  return value
      .whereType<Map>()
      .map((item) => builder(_map(item)))
      .toList(growable: false);
}

String _healthStatus(Object? value) {
  final status = _string(value, fallback: 'unknown').toLowerCase();
  if (const {'healthy', 'warning', 'critical', 'unknown'}.contains(status)) {
    return status;
  }
  return 'unknown';
}
