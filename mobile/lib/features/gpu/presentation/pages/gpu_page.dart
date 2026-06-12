import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/byte_format.dart';
import '../../../../core/utils/percentage_format.dart';
import '../../../../core/utils/temperature_format.dart';
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
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
              children: [
                SizedBox(
                  width: 320,
                  child: MetricCard(
                    title: 'Model',
                    value: gpu.name ?? 'N/A',
                    icon: Icons.developer_board,
                    maxValueLines: 2,
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: MetricCard(
                    title: 'Driver',
                    value: gpu.driverVersion ?? 'N/A',
                    icon: Icons.badge,
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: MetricCard(
                    title: 'Utilization',
                    value: formatPercent(gpu.utilizationPercent),
                    progress: gpu.utilizationPercent,
                    tone: _usageTone(gpu.utilizationPercent),
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: MetricCard(
                    title: 'Temperature',
                    value: formatTemperature(gpu.temperatureC),
                    tone: _tempTone(gpu.temperatureC),
                  ),
                ),
                SizedBox(
                  width: 240,
                  child: MetricCard(
                    title: 'VRAM',
                    value: formatPercent(gpu.memoryUsedPercent),
                    subtitle:
                        '${formatMegabytes(gpu.memoryUsedMb)} / ${formatMegabytes(gpu.memoryTotalMb)}',
                    progress: gpu.memoryUsedPercent,
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: MetricCard(
                    title: 'Power',
                    value: gpu.powerUsageW == null
                        ? 'N/A'
                        : '${gpu.powerUsageW!.toStringAsFixed(1)} W',
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: MetricCard(
                    title: 'Fan',
                    value: formatPercent(gpu.fanSpeedPercent),
                  ),
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

  StatusTone _usageTone(num? value) {
    if (value == null) {
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

  StatusTone _tempTone(num? value) {
    if (value == null) {
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
}
