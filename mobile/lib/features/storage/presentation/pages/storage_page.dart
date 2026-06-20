import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/byte_format.dart';
import '../../../../core/utils/temperature_format.dart';
import '../../../../core/utils/threshold_tone.dart';
import '../../../../core/widgets/info_row.dart';
import '../../../../core/widgets/section_card.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../../core/widgets/status_tone.dart';
import '../../../dashboard/domain/models/monitoring_models.dart';
import '../../../dashboard/presentation/providers/monitoring_controller.dart';
import '../../../dashboard/presentation/widgets/resource_status_view.dart';

enum DiskSort { health, temperature, device, capacity }

class StoragePage extends ConsumerStatefulWidget {
  const StoragePage({super.key});

  @override
  ConsumerState<StoragePage> createState() => _StoragePageState();
}

class _StoragePageState extends ConsumerState<StoragePage> {
  DiskSort _sort = DiskSort.health;

  @override
  Widget build(BuildContext context) {
    final systemState = ref.watch(monitoringControllerProvider).system;
    return ResourceStatusView<SystemResponse>(
      state: systemState,
      onRetry: () =>
          ref.read(monitoringControllerProvider.notifier).fetchSystem(),
      builder: (system) {
        final physicalDisks = [...system.physicalDisks]..sort(_compareDisks);
        final visibleFilesystems = system.disks
            .where((disk) => !_isHiddenMount(disk.mountpoint))
            .toList(growable: false);
        return ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            SectionCard(
              title: 'Mounted Filesystems',
              child: Column(
                children: [
                  for (final disk in visibleFilesystems)
                    Card(
                      child: ListTile(
                        leading: Icon(
                          _highlightMount(disk.mountpoint)
                              ? Icons.star
                              : Icons.storage,
                        ),
                        title: Text('${disk.mountpoint} (${disk.device})'),
                        subtitle: Text(
                          '${disk.fstype} | ${formatBytes(disk.used)} used | ${formatBytes(disk.free)} free | RAID ${disk.raidArray ?? 'No'}',
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${disk.percent.toStringAsFixed(1)}%',
                              style: TextStyle(
                                color: toneColor(thresholdTone(disk.percent)),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            StatusBadge(
                              label: disk.health.status,
                              tone: disk.health.tone,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            SectionCard(
              title: 'RAID Arrays',
              child: system.raidArrays.isEmpty
                  ? const Text('No RAID arrays reported.')
                  : Column(
                      children: [
                        for (final raid in system.raidArrays)
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(AppSpacing.md),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '${raid.name} ${raid.device}',
                                          style: Theme.of(
                                            context,
                                          ).textTheme.titleMedium,
                                        ),
                                      ),
                                      StatusBadge(
                                        label: raid.health.status,
                                        tone: raid.health.tone,
                                      ),
                                    ],
                                  ),
                                  InfoRow(label: 'Level', value: raid.level),
                                  InfoRow(label: 'State', value: raid.state),
                                  InfoRow(
                                    label: 'Expected disks',
                                    value: '${raid.raidDisks}',
                                  ),
                                  InfoRow(
                                    label: 'Active disks',
                                    value: '${raid.activeDevices}',
                                  ),
                                  InfoRow(
                                    label: 'Degraded disks',
                                    value: '${raid.degradedDevices}',
                                  ),
                                  InfoRow(
                                    label: 'Sync action',
                                    value: raid.syncAction ?? 'N/A',
                                  ),
                                  InfoRow(
                                    label: 'Members',
                                    value: raid.members.isEmpty
                                        ? 'N/A'
                                        : raid.members.join(', '),
                                  ),
                                  InfoRow(
                                    label: 'Health reason',
                                    value: raid.health.reason,
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
            SectionCard(
              title: 'Physical Disks',
              trailing: DropdownButton<DiskSort>(
                value: _sort,
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _sort = value);
                  }
                },
                items: const [
                  DropdownMenuItem(
                    value: DiskSort.health,
                    child: Text('Health'),
                  ),
                  DropdownMenuItem(
                    value: DiskSort.temperature,
                    child: Text('Temperature'),
                  ),
                  DropdownMenuItem(
                    value: DiskSort.device,
                    child: Text('Device'),
                  ),
                  DropdownMenuItem(
                    value: DiskSort.capacity,
                    child: Text('Capacity'),
                  ),
                ],
              ),
              child: Column(
                children: [
                  for (final disk in physicalDisks)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${disk.device} ${disk.model ?? ''}'.trim(),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                ),
                                StatusBadge(
                                  label: disk.health.status,
                                  tone: disk.health.tone,
                                ),
                              ],
                            ),
                            InfoRow(
                              label: 'Vendor',
                              value: disk.vendor ?? 'N/A',
                            ),
                            InfoRow(
                              label: 'Serial',
                              value: disk.serial ?? 'N/A',
                            ),
                            InfoRow(
                              label: 'Capacity',
                              value: formatBytes(disk.sizeBytes),
                            ),
                            InfoRow(label: 'Type', value: disk.diskType),
                            InfoRow(
                              label: 'Temperature',
                              value: formatTemperature(disk.temperatureC),
                            ),
                            InfoRow(
                              label: 'Mounted partitions',
                              value: disk.mountedPartitions.isEmpty
                                  ? 'None'
                                  : disk.mountedPartitions.join(', '),
                            ),
                            InfoRow(
                              label: 'RAID arrays',
                              value: disk.raidArrays.isEmpty
                                  ? 'No'
                                  : disk.raidArrays.join(', '),
                            ),
                            InfoRow(
                              label: 'Kernel state',
                              value: disk.state ?? 'N/A',
                            ),
                            InfoRow(
                              label: 'Health reason',
                              value: disk.health.reason,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  bool _highlightMount(String mountpoint) {
    return const {'/', '/mnt/warm', '/mnt/storage'}.contains(mountpoint);
  }

  bool _isHiddenMount(String mountpoint) {
    return mountpoint == '/srv/sftp/tablet_sftp/WarmStorage' ||
        mountpoint.startsWith('/srv/sftp/');
  }

  int _compareDisks(PhysicalDiskMetrics a, PhysicalDiskMetrics b) {
    return switch (_sort) {
      DiskSort.temperature => (b.temperatureC ?? -1).compareTo(
        a.temperatureC ?? -1,
      ),
      DiskSort.device => a.device.compareTo(b.device),
      DiskSort.capacity => b.sizeBytes.compareTo(a.sizeBytes),
      DiskSort.health => _healthRank(
        a.health.status,
      ).compareTo(_healthRank(b.health.status)),
    };
  }

  int _healthRank(String status) {
    return switch (status) {
      'critical' => 0,
      'warning' => 1,
      'unknown' => 2,
      _ => 3,
    };
  }
}
