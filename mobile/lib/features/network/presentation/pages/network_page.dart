import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

class NetworkPage extends ConsumerWidget {
  const NetworkPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          GridView.count(
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
              ),
              MetricChart(
                title: 'Transmit Throughput',
                samples: state.networkSendHistory,
                color: AppColors.accent,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          const SectionCard(
            title: 'Known Devices',
            child: Text(
              'Known-device status will use the restricted control agent in Phase 7. This app does not pretend to provide a full router inventory without router API access.',
            ),
          ),
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
