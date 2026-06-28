import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/byte_format.dart';
import '../../../../core/utils/percentage_format.dart';
import '../../../../core/utils/temperature_format.dart';
import '../../../../core/utils/threshold_tone.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/metric_card.dart';
import '../../../../core/widgets/status_tone.dart';
import '../../../dashboard/domain/models/monitoring_models.dart';
import '../../../dashboard/presentation/providers/monitoring_controller.dart';
import '../../../dashboard/presentation/widgets/metric_chart.dart';
import '../../../dashboard/presentation/widgets/resource_status_view.dart';

class GpuPage extends ConsumerWidget {
  const GpuPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(monitoringControllerProvider);
    return ResourceStatusView<GpuResponse>(
      state: state.gpu,
      onRetry: () => ref.read(monitoringControllerProvider.notifier).fetchGpu(),
      builder: (gpu) {
        if (!gpu.available) {
          return EmptyState(
            icon: Icons.developer_board_off,
            title: 'GPU telemetry unavailable',
            message:
                gpu.reason ??
                'NVML is unavailable or no NVIDIA GPU was detected.',
          );
        }
        return ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            _GpuMetricGrid(
              children: [
                MetricCard(
                  title: 'Model',
                  value: gpu.name ?? 'N/A',
                  icon: Icons.developer_board,
                  maxValueLines: 2,
                ),
                MetricCard(
                  title: 'Driver',
                  value: gpu.driverVersion ?? 'N/A',
                  icon: Icons.badge,
                ),
                MetricCard(
                  title: 'Utilization',
                  value: formatPercent(gpu.utilizationPercent),
                  valueTone: thresholdTone(gpu.utilizationPercent),
                  progress: gpu.utilizationPercent,
                  progressColor: toneColor(
                    thresholdTone(gpu.utilizationPercent),
                  ),
                ),
                MetricCard(
                  title: 'Temperature',
                  value: formatTemperature(gpu.temperatureC),
                  valueTone: temperatureTone(gpu.temperatureC),
                ),
                MetricCard(
                  title: 'VRAM',
                  value: formatPercent(gpu.memoryUsedPercent),
                  valueTone: thresholdTone(gpu.memoryUsedPercent),
                  subtitle:
                      '${formatMegabytes(gpu.memoryUsedMb)} / ${formatMegabytes(gpu.memoryTotalMb)}',
                  progress: gpu.memoryUsedPercent,
                  progressColor: toneColor(
                    thresholdTone(gpu.memoryUsedPercent),
                  ),
                ),
                MetricCard(
                  title: 'Power',
                  value: gpu.powerUsageW == null
                      ? 'N/A'
                      : '${gpu.powerUsageW!.toStringAsFixed(1)} W',
                ),
                MetricCard(
                  title: 'Fan',
                  value: formatPercent(gpu.fanSpeedPercent),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            GridView.count(
              crossAxisCount: MediaQuery.sizeOf(context).width >= 1000 ? 2 : 1,
              crossAxisSpacing: AppSpacing.md,
              mainAxisSpacing: AppSpacing.md,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 2.2,
              children: [
                MetricChart(
                  title: 'GPU Utilization',
                  samples: state.gpuUtilizationHistory,
                  color: AppColors.accent,
                  valueType: MetricChartValueType.percent,
                ),
                MetricChart(
                  title: 'GPU Temperature',
                  samples: state.gpuTemperatureHistory,
                  color: AppColors.warning,
                  valueType: MetricChartValueType.temperatureC,
                ),
                MetricChart(
                  title: 'VRAM Usage',
                  samples: state.gpuVramHistory,
                  color: AppColors.healthy,
                  valueType: MetricChartValueType.percent,
                ),
                MetricChart(
                  title: 'Power Usage',
                  samples: state.gpuPowerHistory,
                  color: AppColors.critical,
                  valueType: MetricChartValueType.watts,
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _GpuMetricGrid extends StatelessWidget {
  const _GpuMetricGrid({required this.children});

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
