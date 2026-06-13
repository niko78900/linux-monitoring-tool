import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../../core/config/app_settings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/byte_format.dart';
import '../../../../core/utils/duration_format.dart';
import '../../../../core/utils/percentage_format.dart';
import '../../../../core/utils/temperature_format.dart';
import '../../../../core/widgets/metric_card.dart';
import '../../../../core/widgets/section_card.dart';
import '../../../../core/widgets/status_tone.dart';
import '../providers/monitoring_controller.dart';
import '../widgets/health_strip.dart';
import '../widgets/metric_chart.dart';
import '../widgets/stale_banner.dart';

class OverviewPage extends ConsumerStatefulWidget {
  const OverviewPage({super.key});

  @override
  ConsumerState<OverviewPage> createState() => _OverviewPageState();
}

class _OverviewPageState extends ConsumerState<OverviewPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncWakelock());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncWakelock();
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AppSettings>(
      settingsControllerProvider,
      (_, next) => _syncWakelock(),
    );
    final state = ref.watch(monitoringControllerProvider);
    final settings = ref.watch(settingsControllerProvider);
    final summary = state.summary.data;
    final system = state.system.data;
    final gpu = state.gpu.data;
    final docker = state.docker.data;

    return RefreshIndicator(
      onRefresh: () =>
          ref.read(monitoringControllerProvider.notifier).refreshAll(),
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          _Header(
            hostname: summary?.hostname ?? system?.hostname ?? 'Homelab server',
            reachable: state.serverReachable,
            lastRefresh: state.lastRefresh,
            pollingMs: settings.summaryPollingMs,
            onRefresh: () =>
                ref.read(monitoringControllerProvider.notifier).refreshAll(),
            onPollingChanged: (value) {
              ref
                  .read(settingsControllerProvider.notifier)
                  .save(settings.copyWith(summaryPollingMs: value));
            },
          ),
          const SizedBox(height: AppSpacing.md),
          StaleBanner(
            states: [
              state.summary,
              state.system,
              state.gpu,
              state.docker,
              state.health,
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          HealthStrip(state: state),
          const SizedBox(height: AppSpacing.lg),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => context.go('/history'),
              icon: const Icon(Icons.query_stats),
              label: const Text('View history'),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (state.firstLoadPending)
            const Center(child: CircularProgressIndicator())
          else if (state.globalError != null)
            SectionCard(
              title: 'Server unreachable',
              child: Text(
                state.globalError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          _MetricGrid(
            children: [
              MetricCard(
                title: 'CPU Usage',
                value: formatPercent(summary?.cpuPercent),
                icon: Icons.speed,
                progress: summary?.cpuPercent,
                tone: _usageTone(summary?.cpuPercent),
              ),
              MetricCard(
                title: 'CPU Temp',
                value: formatTemperature(system?.cpu.temperatureC),
                icon: Icons.thermostat,
                tone: _temperatureTone(system?.cpu.temperatureC),
              ),
              MetricCard(
                title: 'Memory',
                value: formatPercent(summary?.memoryPercent),
                subtitle: system == null
                    ? null
                    : '${formatBytes(system.memory.used)} used of ${formatBytes(system.memory.total)}',
                icon: Icons.memory,
                progress: summary?.memoryPercent,
                tone: _usageTone(summary?.memoryPercent),
              ),
              MetricCard(
                title: 'Swap',
                value: formatPercent(system?.swap.percent),
                subtitle: system == null
                    ? null
                    : '${formatBytes(system.swap.used)} used of ${formatBytes(system.swap.total)}',
                icon: Icons.swap_horiz,
                progress: system?.swap.percent,
                tone: _usageTone(system?.swap.percent),
              ),
              MetricCard(
                title: 'Primary Disk',
                value: formatPercent(summary?.diskPercent),
                subtitle: system == null
                    ? null
                    : '${system.disk.mountpoint} | ${formatBytes(system.disk.free)} free',
                icon: Icons.storage,
                progress: summary?.diskPercent,
                tone: _usageTone(summary?.diskPercent),
              ),
              if (gpu?.available == true)
                MetricCard(
                  title: 'GPU Utilization',
                  value: formatPercent(gpu?.utilizationPercent),
                  icon: Icons.developer_board,
                  progress: gpu?.utilizationPercent,
                  tone: _usageTone(gpu?.utilizationPercent),
                ),
              if (gpu?.available == true)
                MetricCard(
                  title: 'GPU Temp',
                  value: formatTemperature(gpu?.temperatureC),
                  icon: Icons.device_thermostat,
                  tone: _temperatureTone(gpu?.temperatureC),
                ),
              if (gpu?.available == true)
                MetricCard(
                  title: 'GPU VRAM',
                  value: formatPercent(gpu?.memoryUsedPercent),
                  subtitle:
                      '${formatMegabytes(gpu?.memoryUsedMb)} / ${formatMegabytes(gpu?.memoryTotalMb)}',
                  icon: Icons.sd_storage,
                  progress: gpu?.memoryUsedPercent,
                  tone: _usageTone(gpu?.memoryUsedPercent),
                ),
              MetricCard(
                title: 'Uptime',
                value:
                    summary?.uptimeHuman ??
                    formatDurationSeconds(system?.uptimeSeconds),
                icon: Icons.schedule,
              ),
              MetricCard(
                title: 'Network RX/TX',
                value:
                    '${formatBytes(state.throughput.receiveBytesPerSecond)}/s',
                subtitle:
                    'TX ${formatBytes(state.throughput.sendBytesPerSecond)}/s',
                icon: Icons.swap_vert,
              ),
              MetricCard(
                title: 'Docker',
                value: docker?.dockerAvailable == true
                    ? 'Online'
                    : 'Unavailable',
                subtitle: docker == null
                    ? null
                    : '${docker.runningCount}/${docker.containerCount} running',
                icon: Icons.view_in_ar,
                tone: docker?.dockerAvailable == true
                    ? StatusTone.healthy
                    : StatusTone.unknown,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          _ChartGrid(
            children: [
              MetricChart(
                title: 'CPU Usage',
                samples: state.cpuHistory,
                color: AppColors.accent,
                valueType: MetricChartValueType.percent,
              ),
              MetricChart(
                title: 'CPU Temperature',
                samples: state.cpuTemperatureHistory,
                color: AppColors.warning,
                valueType: MetricChartValueType.temperatureC,
              ),
              MetricChart(
                title: 'Memory Usage',
                samples: state.memoryHistory,
                color: AppColors.healthy,
                valueType: MetricChartValueType.percent,
              ),
              if (gpu?.available == true)
                MetricChart(
                  title: 'GPU Utilization',
                  samples: state.gpuUtilizationHistory,
                  valueType: MetricChartValueType.percent,
                ),
              if (gpu?.available == true)
                MetricChart(
                  title: 'GPU Temperature',
                  samples: state.gpuTemperatureHistory,
                  color: AppColors.warning,
                  valueType: MetricChartValueType.temperatureC,
                ),
              MetricChart(
                title: 'Network Receive',
                samples: state.networkReceiveHistory,
                color: AppColors.healthy,
                valueType: MetricChartValueType.bytesPerSecond,
              ),
              MetricChart(
                title: 'Network Send',
                samples: state.networkSendHistory,
                color: AppColors.accent,
                valueType: MetricChartValueType.bytesPerSecond,
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _syncWakelock() {
    if (!mounted) {
      return;
    }
    final settings = ref.read(settingsControllerProvider);
    if (settings.keepScreenAwakeOnOverview) {
      WakelockPlus.enable();
    } else {
      WakelockPlus.disable();
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.hostname,
    required this.reachable,
    required this.lastRefresh,
    required this.pollingMs,
    required this.onRefresh,
    required this.onPollingChanged,
  });

  final String hostname;
  final bool reachable;
  final DateTime? lastRefresh;
  final int pollingMs;
  final VoidCallback onRefresh;
  final ValueChanged<int> onPollingChanged;

  @override
  Widget build(BuildContext context) {
    final formatter = DateFormat.Hms();
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(hostname, style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '${reachable ? 'API reachable' : 'Server unreachable'} | Last refresh ${lastRefresh == null ? 'N/A' : formatter.format(lastRefresh!)}',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
              ),
            ],
          ),
        ),
        DropdownButton<int>(
          value: pollingMs,
          items: const [
            DropdownMenuItem(value: 1000, child: Text('1 sec')),
            DropdownMenuItem(value: 3000, child: Text('3 sec')),
            DropdownMenuItem(value: 5000, child: Text('5 sec')),
            DropdownMenuItem(value: 10000, child: Text('10 sec')),
            DropdownMenuItem(value: 30000, child: Text('30 sec')),
            DropdownMenuItem(value: 60000, child: Text('1 min')),
          ],
          onChanged: (value) {
            if (value != null) {
              onPollingChanged(value);
            }
          },
        ),
        const SizedBox(width: AppSpacing.sm),
        FilledButton.icon(
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh),
          label: const Text('Refresh'),
        ),
      ],
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1100
            ? 4
            : constraints.maxWidth >= 760
            ? 3
            : 1;
        return GridView.count(
          crossAxisCount: columns,
          crossAxisSpacing: AppSpacing.md,
          mainAxisSpacing: AppSpacing.md,
          childAspectRatio: columns == 1 ? 2.8 : 1.55,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: children,
        );
      },
    );
  }
}

class _ChartGrid extends StatelessWidget {
  const _ChartGrid({required this.children});

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

StatusTone _usageTone(num? value) {
  if (value == null || value.isNaN) {
    return StatusTone.neutral;
  }
  if (value >= 90) {
    return StatusTone.critical;
  }
  if (value >= 70) {
    return StatusTone.warning;
  }
  return StatusTone.healthy;
}

StatusTone _temperatureTone(num? value) {
  if (value == null || value.isNaN) {
    return StatusTone.neutral;
  }
  if (value >= 85) {
    return StatusTone.critical;
  }
  if (value >= 70) {
    return StatusTone.warning;
  }
  return StatusTone.healthy;
}
