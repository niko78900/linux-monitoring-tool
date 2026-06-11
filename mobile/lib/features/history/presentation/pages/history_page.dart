import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/temperature_format.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/section_card.dart';
import '../../domain/models/history_models.dart';
import '../providers/history_providers.dart';
import '../widgets/history_chart.dart';

class HistoryPage extends ConsumerStatefulWidget {
  const HistoryPage({super.key});

  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
  HistoryRangeValue _selectedRange = HistoryRangeValue.twentyFourHours;
  String _selectedMountpoint = '/mnt/storage';
  String? _selectedDisk;
  String? _selectedRaidArray;

  @override
  Widget build(BuildContext context) {
    final rangesState = ref.watch(historyRangesProvider);
    final inventoryState = ref.watch(historyInventoryProvider);

    rangesState.whenData((ranges) {
      if (ranges.ranges.isNotEmpty &&
          !ranges.ranges.any((item) => item.range == _selectedRange)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() => _selectedRange = ranges.defaultRange);
          }
        });
      }
    });

    inventoryState.whenData((inventory) {
      final mountpoints = inventory.mountpoints;
      if (mountpoints.isNotEmpty &&
          !mountpoints.contains(_selectedMountpoint)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() => _selectedMountpoint = mountpoints.first);
          }
        });
      }
      if (_selectedDisk == null && inventory.diskDevices.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() => _selectedDisk = inventory.diskDevices.first);
          }
        });
      }
      if (_selectedRaidArray == null && inventory.raidArrays.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() => _selectedRaidArray = inventory.raidArrays.first);
          }
        });
      }
    });

    final availableRanges = rangesState.maybeWhen(
      data: (data) => data.ranges.map((item) => item.range).toList(growable: false),
      orElse: () => HistoryRangeValue.values,
    );
    final mountpoints = inventoryState.maybeWhen(
      data: (data) => data.mountpoints,
      orElse: () => const ['/', '/mnt/warm', '/mnt/storage'],
    );
    final diskDevices = inventoryState.maybeWhen(
      data: (data) => data.diskDevices,
      orElse: () => const <String>[],
    );
    final raidArrays = inventoryState.maybeWhen(
      data: (data) => data.raidArrays,
      orElse: () => const <String>[],
    );

    final overviewState = ref.watch(overviewHistoryProvider(_selectedRange));
    final storageState = ref.watch(
      storageHistoryProvider((
        range: _selectedRange,
        mountpoint: _selectedMountpoint,
      )),
    );
    final diskState = _selectedDisk == null
        ? null
        : ref.watch(
            diskHistoryProvider((
              range: _selectedRange,
              device: _selectedDisk!,
            )),
          );
    final raidState = _selectedRaidArray == null
        ? null
        : ref.watch(
            raidHistoryProvider((
              range: _selectedRange,
              arrayName: _selectedRaidArray!,
            )),
          );

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'History',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            IconButton(
              tooltip: 'Back to overview',
              onPressed: () => context.go('/overview'),
              icon: const Icon(Icons.dashboard),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<HistoryRangeValue>(
            segments: [
              for (final range in availableRanges)
                ButtonSegment(
                  value: range,
                  label: Text(range.label),
                ),
            ],
            selected: {_selectedRange},
            onSelectionChanged: (selection) {
              final value = _firstOrNull(selection);
              if (value != null) {
                setState(() => _selectedRange = value);
              }
            },
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        SectionCard(
          title: 'Overview',
          child: _AsyncHistorySection<HistoryOverviewResponseModel>(
            state: overviewState,
            builder: (history) => _HistoryChartGrid(
              children: [
                HistoryChart(
                  title: 'CPU Usage',
                  points: [
                    for (final point in history.points)
                      HistoryChartPoint(
                        timestamp: point.timestamp,
                        value: point.cpuPercentAvg,
                      ),
                  ],
                  maxY: 100,
                ),
                HistoryChart(
                  title: 'CPU Temperature',
                  points: [
                    for (final point in history.points)
                      HistoryChartPoint(
                        timestamp: point.timestamp,
                        value: point.cpuTemperatureCAvg,
                      ),
                  ],
                  maxY: 110,
                  color: AppColors.warning,
                ),
                HistoryChart(
                  title: 'Memory Usage',
                  points: [
                    for (final point in history.points)
                      HistoryChartPoint(
                        timestamp: point.timestamp,
                        value: point.memoryPercentAvg,
                      ),
                  ],
                  maxY: 100,
                  color: AppColors.healthy,
                ),
                HistoryChart(
                  title: 'Swap Usage',
                  points: [
                    for (final point in history.points)
                      HistoryChartPoint(
                        timestamp: point.timestamp,
                        value: point.swapPercentAvg,
                      ),
                  ],
                  maxY: 100,
                  color: AppColors.textMuted,
                ),
                HistoryChart(
                  title: 'GPU Utilization',
                  points: [
                    for (final point in history.points)
                      HistoryChartPoint(
                        timestamp: point.timestamp,
                        value: point.gpuUtilizationPercentAvg,
                      ),
                  ],
                  maxY: 100,
                ),
                HistoryChart(
                  title: 'GPU Temperature',
                  points: [
                    for (final point in history.points)
                      HistoryChartPoint(
                        timestamp: point.timestamp,
                        value: point.gpuTemperatureCAvg,
                      ),
                  ],
                  maxY: 110,
                  color: AppColors.warning,
                ),
                HistoryChart(
                  title: 'GPU VRAM Used (MB)',
                  points: [
                    for (final point in history.points)
                      HistoryChartPoint(
                        timestamp: point.timestamp,
                        value: point.gpuMemoryUsedMbAvg,
                      ),
                  ],
                  color: AppColors.healthy,
                ),
                HistoryChart(
                  title: 'Network Receive',
                  points: [
                    for (final point in history.points)
                      HistoryChartPoint(
                        timestamp: point.timestamp,
                        value: point.networkRecvBytesPerSecondAvg,
                      ),
                  ],
                  color: AppColors.healthy,
                ),
                HistoryChart(
                  title: 'Network Send',
                  points: [
                    for (final point in history.points)
                      HistoryChartPoint(
                        timestamp: point.timestamp,
                        value: point.networkSendBytesPerSecondAvg,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        SectionCard(
          title: 'Storage',
          trailing: SizedBox(
            width: 220,
            child: DropdownButton<String>(
              value: mountpoints.contains(_selectedMountpoint)
                  ? _selectedMountpoint
                  : _firstOrNull(mountpoints),
              hint: const Text('Mountpoint'),
              isExpanded: true,
              items: [
                for (final mountpoint in mountpoints)
                  DropdownMenuItem(
                    value: mountpoint,
                    child: Text(mountpoint),
                  ),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _selectedMountpoint = value);
                }
              },
            ),
          ),
          child: _AsyncHistorySection<StorageHistoryResponseModel>(
            state: storageState,
            builder: (history) {
              final latest = history.points.lastOrNull;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (latest != null)
                    Text(
                      'Latest: ${latest.healthStatus} | ${latest.readOnlyAny ? 'Read-only' : 'Read-write visible'} | ${latest.availableAny ? 'Available' : 'Unavailable'}',
                    ),
                  const SizedBox(height: AppSpacing.md),
                  _HistoryChartGrid(
                    children: [
                      HistoryChart(
                        title: 'Usage %',
                        points: [
                          for (final point in history.points)
                            HistoryChartPoint(
                              timestamp: point.timestamp,
                              value: point.percentAvg,
                            ),
                        ],
                        maxY: 100,
                      ),
                      HistoryChart(
                        title: 'Used Space',
                        points: [
                          for (final point in history.points)
                            HistoryChartPoint(
                              timestamp: point.timestamp,
                              value: point.usedBytesAvg,
                            ),
                        ],
                        color: AppColors.warning,
                      ),
                      HistoryChart(
                        title: 'Free Space',
                        points: [
                          for (final point in history.points)
                            HistoryChartPoint(
                              timestamp: point.timestamp,
                              value: point.freeBytesAvg,
                            ),
                        ],
                        color: AppColors.healthy,
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        SectionCard(
          title: 'Disks',
          trailing: SizedBox(
            width: 220,
            child: DropdownButton<String>(
              value: diskDevices.contains(_selectedDisk)
                  ? _selectedDisk
                  : _firstOrNull(diskDevices),
              hint: const Text('Disk'),
              isExpanded: true,
              items: [
                for (final device in diskDevices)
                  DropdownMenuItem(
                    value: device,
                    child: Text(device),
                  ),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _selectedDisk = value);
                }
              },
            ),
          ),
          child: diskState == null
              ? const Text('No physical disks reported.')
              : _AsyncHistorySection<DiskHistoryResponseModel>(
                  state: diskState,
                  builder: (history) {
                    final latest = history.points.lastOrNull;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (latest != null)
                          Text(
                            'Latest: ${latest.healthStatus} | ${latest.kernelState ?? 'Unknown kernel state'} | ${formatTemperature(latest.temperatureCAvg)}',
                          ),
                        const SizedBox(height: AppSpacing.md),
                        _HistoryChartGrid(
                          children: [
                            HistoryChart(
                              title: 'Disk Temperature',
                              points: [
                                for (final point in history.points)
                                  HistoryChartPoint(
                                    timestamp: point.timestamp,
                                    value: point.temperatureCAvg,
                                  ),
                              ],
                              maxY: 110,
                              color: AppColors.warning,
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
        ),
        const SizedBox(height: AppSpacing.lg),
        SectionCard(
          title: 'RAID',
          trailing: SizedBox(
            width: 220,
            child: DropdownButton<String>(
              value: raidArrays.contains(_selectedRaidArray)
                  ? _selectedRaidArray
                  : _firstOrNull(raidArrays),
              hint: const Text('Array'),
              isExpanded: true,
              items: [
                for (final array in raidArrays)
                  DropdownMenuItem(
                    value: array,
                    child: Text(array),
                  ),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _selectedRaidArray = value);
                }
              },
            ),
          ),
          child: raidState == null
              ? const Text('No RAID arrays reported.')
              : _AsyncHistorySection<RaidHistoryResponseModel>(
                  state: raidState,
                  builder: (history) {
                    final latest = history.points.lastOrNull;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (latest != null)
                          Text(
                            'Latest: ${latest.healthStatus} | ${latest.state ?? 'Unknown state'} | ${latest.syncAction ?? 'No sync action'}',
                          ),
                        const SizedBox(height: AppSpacing.md),
                        _HistoryChartGrid(
                          children: [
                            HistoryChart(
                              title: 'Degraded Disks',
                              points: [
                                for (final point in history.points)
                                  HistoryChartPoint(
                                    timestamp: point.timestamp,
                                    value: point.degradedDevicesAvg,
                                  ),
                              ],
                              color: AppColors.warning,
                            ),
                            HistoryChart(
                              title: 'Active Disks',
                              points: [
                                for (final point in history.points)
                                  HistoryChartPoint(
                                    timestamp: point.timestamp,
                                    value: point.activeDevicesAvg,
                                  ),
                              ],
                              color: AppColors.healthy,
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }
}

T? _firstOrNull<T>(Iterable<T> values) {
  if (values.isEmpty) {
    return null;
  }
  return values.first;
}

class _AsyncHistorySection<T> extends StatelessWidget {
  const _AsyncHistorySection({
    required this.state,
    required this.builder,
  });

  final AsyncValue<CachedHistoryData<T>> state;
  final Widget Function(T data) builder;

  @override
  Widget build(BuildContext context) {
    return state.when(
      data: (payload) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (payload.fromCache)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Text(
                'Cached history | Last refreshed ${_formatCachedAt(payload.cachedAt)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.warning,
                ),
              ),
            ),
          builder(payload.data),
        ],
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => EmptyState(
        icon: Icons.query_stats,
        title: 'History unavailable',
        message: _describeError(error),
      ),
    );
  }

  String _formatCachedAt(DateTime? value) {
    if (value == null) {
      return 'unknown';
    }
    return DateFormat.yMd().add_Hm().format(value.toLocal());
  }

  String _describeError(Object error) {
    if (error is AppException) {
      return error.message;
    }
    return error.toString();
  }
}

class _HistoryChartGrid extends StatelessWidget {
  const _HistoryChartGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1000 ? 2 : 1;
        return GridView.count(
          crossAxisCount: columns,
          crossAxisSpacing: AppSpacing.md,
          mainAxisSpacing: AppSpacing.md,
          childAspectRatio: columns == 1 ? 2.4 : 2.2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: children,
        );
      },
    );
  }
}
