import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../../core/config/app_settings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/byte_format.dart';
import '../../../../core/utils/display_name_format.dart';
import '../../../../core/utils/duration_format.dart';
import '../../../../core/utils/percentage_format.dart';
import '../../../../core/utils/temperature_format.dart';
import '../../../../core/utils/threshold_tone.dart';
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
            hostname: formatHostDisplayName(
              summary?.hostname ?? system?.hostname ?? 'Homelab server',
            ),
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
                valueTone: _usageTone(summary?.cpuPercent),
                onTap: () => context.go('/hardware'),
              ),
              MetricCard(
                title: 'CPU Temp',
                value: formatTemperature(system?.cpu.temperatureC),
                icon: Icons.thermostat,
                tone: _temperatureTone(system?.cpu.temperatureC),
                valueTone: _temperatureTone(system?.cpu.temperatureC),
                onTap: () => context.go('/hardware'),
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
                valueTone: _usageTone(summary?.memoryPercent),
                onTap: () => context.go('/hardware'),
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
                valueTone: _usageTone(system?.swap.percent),
                onTap: () => context.go('/storage'),
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
                valueTone: _usageTone(summary?.diskPercent),
                onTap: () => context.go('/storage'),
              ),
              if (gpu?.available == true)
                MetricCard(
                  title: 'GPU Utilization',
                  value: formatPercent(gpu?.utilizationPercent),
                  icon: Icons.developer_board,
                  progress: gpu?.utilizationPercent,
                  tone: _usageTone(gpu?.utilizationPercent),
                  valueTone: _usageTone(gpu?.utilizationPercent),
                  onTap: () => context.go('/gpu'),
                ),
              if (gpu?.available == true)
                MetricCard(
                  title: 'GPU Temp',
                  value: formatTemperature(gpu?.temperatureC),
                  icon: Icons.device_thermostat,
                  tone: _temperatureTone(gpu?.temperatureC),
                  valueTone: _temperatureTone(gpu?.temperatureC),
                  onTap: () => context.go('/gpu'),
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
                  valueTone: _usageTone(gpu?.memoryUsedPercent),
                  onTap: () => context.go('/gpu'),
                ),
              MetricCard(
                title: 'Uptime',
                value:
                    summary?.uptimeHuman ??
                    formatDurationSeconds(system?.uptimeSeconds),
                icon: Icons.schedule,
                onTap: () => context.go('/history'),
              ),
              MetricCard(
                title: 'Network RX/TX',
                value:
                    '${formatBytes(state.throughput.receiveBytesPerSecond)}/s',
                subtitle:
                    'TX ${formatBytes(state.throughput.sendBytesPerSecond)}/s',
                icon: Icons.swap_vert,
                onTap: () => context.go('/network'),
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
                onTap: () => context.go('/services'),
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
    final titleBlock = Column(
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
    );
    final controls = Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
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
        FilledButton.icon(
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh),
          label: const Text('Refresh'),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 820) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              titleBlock,
              const SizedBox(height: AppSpacing.md),
              const _LocalStatusCard(),
              const SizedBox(height: AppSpacing.md),
              controls,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: titleBlock),
            const SizedBox(width: AppSpacing.lg),
            const _LocalStatusCard(),
            const SizedBox(width: AppSpacing.lg),
            controls,
          ],
        );
      },
    );
  }
}

class _LocalStatusCard extends StatefulWidget {
  const _LocalStatusCard();

  @override
  State<_LocalStatusCard> createState() => _LocalStatusCardState();
}

class _LocalStatusCardState extends State<_LocalStatusCard> {
  late DateTime _now;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) {
        setState(() => _now = DateTime.now());
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final time = DateFormat.Hm().format(_now);
    final date = DateFormat('EEE, MMM d').format(_now);
    final zone = _now.timeZoneName;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.schedule, color: AppColors.accent),
            const SizedBox(width: AppSpacing.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Local time',
                  style: Theme.of(
                    context,
                  ).textTheme.labelMedium?.copyWith(color: AppColors.textMuted),
                ),
                Text(time, style: Theme.of(context).textTheme.titleLarge),
                Text(
                  '$date | $zone',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
                ),
              ],
            ),
          ],
        ),
      ),
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
  return thresholdTone(value);
}

StatusTone _temperatureTone(num? value) {
  return temperatureTone(value);
}
