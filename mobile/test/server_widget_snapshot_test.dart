import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:homelab_tablet/core/config/app_settings.dart';
import 'package:homelab_tablet/features/dashboard/domain/models/monitoring_models.dart';
import 'package:homelab_tablet/features/server_widget/domain/models/server_widget_snapshot.dart';

void main() {
  test('snapshot serialization round-trips', () {
    const snapshot = ServerWidgetSnapshot(
      hostname: 'homelab',
      serverReachable: true,
      lastUpdatedUtc: null,
      isStale: false,
      cpuPercent: 22,
      cpuTemperatureC: 44,
      memoryPercent: 55,
      gpuAvailable: true,
      gpuUtilizationPercent: 11,
      gpuTemperatureC: 49,
      primaryDiskPercent: 63,
      primaryDiskLabel: '/mnt/storage',
      primaryDiskFreeBytes: 37,
      secondaryDiskPercent: 40,
      secondaryDiskLabel: '/mnt/warm',
      secondaryDiskFreeBytes: 60,
      raidHealth: 'healthy',
      diskHealth: 'healthy',
      networkRecvBytesPerSecond: 1024,
      networkSendBytesPerSecond: 2048,
      networkBytesRecvTotal: 3000,
      networkBytesSentTotal: 4000,
      topNetworkSpeedMbps: 1000,
      sourceNetworkBytesRecvTotal: 3000,
      sourceNetworkBytesSentTotal: 4000,
    );

    final decoded = ServerWidgetSnapshot.fromJson(
      jsonDecode(jsonEncode(snapshot.toJson())) as Map<String, dynamic>,
    );

    expect(decoded.hostname, snapshot.hostname);
    expect(decoded.serverReachable, isTrue);
    expect(decoded.primaryDiskLabel, '/mnt/storage');
    expect(decoded.secondaryDiskLabel, '/mnt/warm');
    expect(decoded.networkSendBytesPerSecond, 2048);
    expect(decoded.topNetworkSpeedMbps, 1000);
  });

  test('snapshot builder handles missing gpu and first-sample throughput', () {
    final settings = AppSettings.defaults();
    final snapshot = ServerWidgetSnapshot.fromMonitoringData(
      summary: _summary(),
      system: _system(),
      settings: settings,
      updatedAt: DateTime.utc(2026, 6, 11, 12),
    );

    expect(snapshot.gpuAvailable, isFalse);
    expect(snapshot.gpuUtilizationPercent, isNull);
    expect(snapshot.gpuTemperatureC, isNull);
    expect(snapshot.networkRecvBytesPerSecond, isNull);
    expect(snapshot.primaryDiskLabel, '/mnt/storage');
    expect(snapshot.primaryDiskFreeBytes, 37);
  });

  test('snapshot builder includes optional secondary storage', () {
    final settings = AppSettings.defaults().copyWith(
      widgetShowSecondaryStorage: true,
      widgetSecondaryStorageMountpoint: '/mnt/warm',
    );
    final snapshot = ServerWidgetSnapshot.fromMonitoringData(
      summary: _summary(),
      system: _system(),
      settings: settings,
      updatedAt: DateTime.utc(2026, 6, 11, 12),
    );

    expect(snapshot.secondaryDiskLabel, '/mnt/warm');
    expect(snapshot.secondaryDiskPercent, 40);
    expect(snapshot.secondaryDiskFreeBytes, 60);
  });

  test('snapshot builder calculates throughput from previous totals', () {
    final settings = AppSettings.defaults();
    final previous = ServerWidgetSnapshot.fromMonitoringData(
      summary: _summary(),
      system: _system(bytesRecv: 1000, bytesSent: 2000),
      settings: settings,
      updatedAt: DateTime.utc(2026, 6, 11, 12),
    );

    final snapshot = ServerWidgetSnapshot.fromMonitoringData(
      summary: _summary(),
      system: _system(bytesRecv: 2500, bytesSent: 5000),
      settings: settings,
      updatedAt: DateTime.utc(2026, 6, 11, 12, 0, 30),
      previous: previous,
    );

    expect(snapshot.networkRecvBytesPerSecond, closeTo(50, 0.001));
    expect(snapshot.networkSendBytesPerSecond, closeTo(100, 0.001));
  });

  test('offline snapshot keeps prior values and marks stale', () {
    final previous = ServerWidgetSnapshot.offlineFromPrevious(
      previous: const ServerWidgetSnapshot(
        hostname: 'homelab',
        serverReachable: true,
        lastUpdatedUtc: null,
        isStale: false,
        cpuPercent: 22,
        cpuTemperatureC: 44,
        memoryPercent: 55,
        gpuAvailable: true,
        gpuUtilizationPercent: 11,
        gpuTemperatureC: 49,
        primaryDiskPercent: 63,
        primaryDiskLabel: '/mnt/storage',
        primaryDiskFreeBytes: 37,
        secondaryDiskPercent: 40,
        secondaryDiskLabel: '/mnt/warm',
        secondaryDiskFreeBytes: 60,
        raidHealth: 'healthy',
        diskHealth: 'healthy',
        networkRecvBytesPerSecond: 1024,
        networkSendBytesPerSecond: 2048,
        networkBytesRecvTotal: 3000,
        networkBytesSentTotal: 4000,
        topNetworkSpeedMbps: 1000,
        sourceNetworkBytesRecvTotal: 3000,
        sourceNetworkBytesSentTotal: 4000,
      ),
    );

    expect(previous.serverReachable, isFalse);
    expect(previous.isStale, isTrue);
    expect(previous.cpuPercent, 22);
    expect(previous.secondaryDiskLabel, '/mnt/warm');
  });

  test('snapshot serialization excludes sensitive values', () {
    const forbidden = [
      'token',
      'fcm_token',
      'control_api_token',
      'ssh_private_key',
      'sftp_private_key',
      'passphrase',
      'shell_output',
      'file_contents',
    ];
    final snapshot = ServerWidgetSnapshot.fromMonitoringData(
      summary: _summary(),
      system: _system(),
      settings: AppSettings.defaults(),
      updatedAt: DateTime.utc(2026, 6, 11, 12),
    );
    final encoded = jsonEncode(snapshot.toJson()).toLowerCase();

    for (final value in forbidden) {
      expect(encoded.contains(value), isFalse);
    }
  });
}

SummaryResponse _summary() {
  return const SummaryResponse(
    hostname: 'homelab',
    uptimeHuman: '1 day',
    cpuPercent: 18,
    memoryPercent: 53,
    diskPercent: 61,
    gpuAvailable: false,
    gpuUtilizationPercent: null,
    gpuTempC: null,
    dockerAvailable: true,
    runningContainers: 5,
  );
}

SystemResponse _system({int bytesRecv = 2000, int bytesSent = 3000}) {
  return SystemResponse(
    hostname: 'homelab',
    os: const PlatformInfo(
      system: 'Linux',
      release: '6.0',
      version: '1',
      machine: 'x86_64',
      platform: 'linux',
    ),
    kernelVersion: '6.0',
    specs: SystemSpecs(
      cpu: const CpuSpecs(
        modelName: 'CPU',
        vendor: 'Vendor',
        architecture: 'x86_64',
        physicalCores: 8,
        logicalCores: 16,
        minFrequencyMhz: null,
        maxFrequencyMhz: null,
        capabilities: [],
      ),
      memoryTotalBytes: 16,
      swapTotalBytes: 8,
      memory: const MemorySpecs(
        totalBytes: 16,
        speedMhz: null,
        memoryType: null,
        manufacturers: [],
        modules: [],
      ),
      motherboard: const MotherboardSpecs(
        vendor: null,
        model: null,
        version: null,
        chipset: null,
      ),
      gpu: const GpuSpecs(
        available: false,
        reason: null,
        brand: null,
        model: null,
        driverVersion: null,
        vramTotalMb: null,
        cudaComputeCapability: null,
        capabilities: [],
      ),
    ),
    chassisTemperatureC: null,
    uptimeSeconds: 1,
    uptimeHuman: '1 day',
    bootTime: DateTime.utc(2026, 6, 10),
    cpu: const CpuMetrics(
      usagePercent: 18,
      physicalCores: 8,
      logicalCores: 16,
      loadAverage: null,
      temperatureC: 42,
    ),
    memory: const MemoryMetrics(
      total: 100,
      available: 50,
      used: 50,
      percent: 50,
    ),
    swap: const SwapMetrics(total: 10, used: 1, percent: 10),
    disk: const DiskMetrics(
      total: 100,
      used: 61,
      free: 39,
      percent: 61,
      mountpoint: '/',
    ),
    disks: const [
      DiskDeviceMetrics(
        device: '/dev/md0',
        mountpoint: '/mnt/storage',
        fstype: 'ext4',
        total: 100,
        used: 63,
        free: 37,
        percent: 63,
        readOnly: false,
        available: true,
        raidArray: 'md0',
        raidLevel: 'raid1',
        health: HealthInfo(status: 'healthy', reason: 'ok'),
      ),
      DiskDeviceMetrics(
        device: '/dev/sdb1',
        mountpoint: '/mnt/warm',
        fstype: 'ext4',
        total: 100,
        used: 40,
        free: 60,
        percent: 40,
        readOnly: false,
        available: true,
        raidArray: null,
        raidLevel: null,
        health: HealthInfo(status: 'healthy', reason: 'ok'),
      ),
    ],
    raidArrays: const [
      RaidArrayMetrics(
        name: 'md0',
        device: '/dev/md0',
        level: 'raid1',
        state: 'clean',
        raidDisks: 2,
        activeDevices: 2,
        degradedDevices: 0,
        syncAction: null,
        members: [],
        health: HealthInfo(status: 'healthy', reason: 'ok'),
      ),
    ],
    physicalDisks: const [
      PhysicalDiskMetrics(
        name: 'sda',
        device: '/dev/sda',
        model: 'disk',
        vendor: null,
        serial: null,
        sizeBytes: 100,
        temperatureC: 35,
        rotational: false,
        removable: false,
        state: 'running',
        mountedPartitions: [],
        raidArrays: [],
        health: HealthInfo(status: 'healthy', reason: 'ok'),
      ),
    ],
    network: NetworkMetrics(
      bytesSent: bytesSent,
      bytesRecv: bytesRecv,
      packetsSent: 10,
      packetsRecv: 10,
      topSpeedMbps: 1000,
    ),
  );
}
