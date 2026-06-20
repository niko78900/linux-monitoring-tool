import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/byte_format.dart';
import '../../../../core/widgets/metric_card.dart';
import '../../../../core/widgets/section_card.dart';
import '../../../../core/widgets/status_tone.dart';
import '../../../dashboard/domain/models/monitoring_models.dart';
import '../../../dashboard/presentation/providers/monitoring_controller.dart';
import '../../../dashboard/presentation/widgets/metric_chart.dart';
import '../../../dashboard/presentation/widgets/resource_status_view.dart';
import '../../../history/domain/models/history_models.dart';
import '../../../history/presentation/providers/history_providers.dart';
import '../../../history/presentation/widgets/history_chart.dart';

class NetworkPage extends ConsumerStatefulWidget {
  const NetworkPage({super.key});

  @override
  ConsumerState<NetworkPage> createState() => _NetworkPageState();
}

class _NetworkPageState extends ConsumerState<NetworkPage> {
  _NetworkRange _range = _NetworkRange.live;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(monitoringControllerProvider);
    return ResourceStatusView<SystemResponse>(
      state: state.system,
      onRetry: () =>
          ref.read(monitoringControllerProvider.notifier).fetchSystem(),
      builder: (system) => ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            children: [
              SizedBox(
                width: 260,
                child: MetricCard(
                  title: 'Current Receive',
                  value:
                      '${formatBytes(state.throughput.receiveBytesPerSecond)}/s',
                  icon: Icons.download,
                  tone: StatusTone.healthy,
                ),
              ),
              SizedBox(
                width: 260,
                child: MetricCard(
                  title: 'Current Send',
                  value:
                      '${formatBytes(state.throughput.sendBytesPerSecond)}/s',
                  icon: Icons.upload,
                  tone: StatusTone.neutral,
                ),
              ),
              SizedBox(
                width: 260,
                child: MetricCard(
                  title: 'Total Received',
                  value: formatBytes(system.network.bytesRecv),
                ),
              ),
              SizedBox(
                width: 260,
                child: MetricCard(
                  title: 'Total Sent',
                  value: formatBytes(system.network.bytesSent),
                ),
              ),
              SizedBox(
                width: 260,
                child: MetricCard(
                  title: 'Packets Received',
                  value: system.network.packetsRecv.toString(),
                ),
              ),
              SizedBox(
                width: 260,
                child: MetricCard(
                  title: 'Packets Sent',
                  value: system.network.packetsSent.toString(),
                ),
              ),
              SizedBox(
                width: 260,
                child: MetricCard(
                  title: 'Top Link Speed',
                  value: _speed(system.network.topSpeedMbps),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: Text(
                  _range == _NetworkRange.live
                      ? 'Live throughput'
                      : 'Historical throughput',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              SegmentedButton<_NetworkRange>(
                segments: const [
                  ButtonSegment(value: _NetworkRange.live, label: Text('Live')),
                  ButtonSegment(value: _NetworkRange.day, label: Text('Day')),
                  ButtonSegment(value: _NetworkRange.week, label: Text('Week')),
                  ButtonSegment(
                    value: _NetworkRange.month,
                    label: Text('Month'),
                  ),
                ],
                selected: {_range},
                onSelectionChanged: (selection) {
                  final next = selection.firstOrNull;
                  if (next != null) {
                    setState(() => _range = next);
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _range == _NetworkRange.live
              ? _LiveNetworkCharts(state: state)
              : _HistoryNetworkCharts(range: _range.historyRange),
        ],
      ),
    );
  }

  String _speed(int? speedMbps) {
    if (speedMbps == null || speedMbps <= 0) {
      return 'N/A';
    }
    if (speedMbps >= 1000) {
      return '${(speedMbps / 1000).toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '')} Gbps';
    }
    return '$speedMbps Mbps';
  }
}

class _LiveNetworkCharts extends StatelessWidget {
  const _LiveNetworkCharts({required this.state});

  final MonitoringState state;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: MediaQuery.sizeOf(context).width >= 1000 ? 2 : 1,
      crossAxisSpacing: AppSpacing.md,
      mainAxisSpacing: AppSpacing.md,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 2.2,
      children: [
        MetricChart(
          title: 'Receive Throughput',
          samples: state.networkReceiveHistory,
          color: AppColors.healthy,
          valueType: MetricChartValueType.bytesPerSecond,
        ),
        MetricChart(
          title: 'Transmit Throughput',
          samples: state.networkSendHistory,
          color: AppColors.accent,
          valueType: MetricChartValueType.bytesPerSecond,
        ),
      ],
    );
  }
}

class _HistoryNetworkCharts extends ConsumerWidget {
  const _HistoryNetworkCharts({required this.range});

  final HistoryRangeValue range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyState = ref.watch(overviewHistoryProvider(range));
    return historyState.when(
      data: (payload) {
        final history = payload.data;
        final last = history.points.lastOrNull?.timestamp;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Showing ${_formatWindow(history.from)} -> ${_formatWindow(history.to)} | ${history.points.length} points | last ${_formatWindow(last)}',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
            ),
            const SizedBox(height: AppSpacing.md),
            GridView.count(
              crossAxisCount: MediaQuery.sizeOf(context).width >= 1000 ? 2 : 1,
              crossAxisSpacing: AppSpacing.md,
              mainAxisSpacing: AppSpacing.md,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 2.2,
              children: [
                HistoryChart(
                  title: 'Receive Throughput',
                  points: [
                    for (final point in history.points)
                      HistoryChartPoint(
                        timestamp: point.timestamp,
                        value: point.networkRecvBytesPerSecondAvg,
                      ),
                  ],
                  color: AppColors.healthy,
                  valueType: MetricChartValueType.bytesPerSecond,
                  windowStart: history.from,
                  windowEnd: history.to,
                  resolutionSeconds: history.resolutionSeconds,
                  range: history.range,
                ),
                HistoryChart(
                  title: 'Transmit Throughput',
                  points: [
                    for (final point in history.points)
                      HistoryChartPoint(
                        timestamp: point.timestamp,
                        value: point.networkSendBytesPerSecondAvg,
                      ),
                  ],
                  color: AppColors.accent,
                  valueType: MetricChartValueType.bytesPerSecond,
                  windowStart: history.from,
                  windowEnd: history.to,
                  resolutionSeconds: history.resolutionSeconds,
                  range: history.range,
                ),
              ],
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => SectionCard(
        title: 'Network history unavailable',
        child: Text(error.toString()),
      ),
    );
  }

  String _formatWindow(DateTime? value) {
    if (value == null) {
      return 'unknown';
    }
    return DateFormat('MMM d HH:mm').format(value.toLocal());
  }
}

enum _NetworkRange {
  live,
  day,
  week,
  month;

  HistoryRangeValue get historyRange {
    return switch (this) {
      _NetworkRange.live => HistoryRangeValue.oneHour,
      _NetworkRange.day => HistoryRangeValue.twentyFourHours,
      _NetworkRange.week => HistoryRangeValue.sevenDays,
      _NetworkRange.month => HistoryRangeValue.thirtyDays,
    };
  }
}
