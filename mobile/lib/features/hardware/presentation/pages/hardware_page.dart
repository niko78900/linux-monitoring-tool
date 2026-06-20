import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/byte_format.dart';
import '../../../../core/utils/temperature_format.dart';
import '../../../../core/utils/threshold_tone.dart';
import '../../../../core/widgets/info_row.dart';
import '../../../../core/widgets/section_card.dart';
import '../../../../core/widgets/status_tone.dart';
import '../../../dashboard/domain/models/monitoring_models.dart';
import '../../../dashboard/presentation/providers/monitoring_controller.dart';
import '../../../dashboard/presentation/widgets/resource_status_view.dart';

class HardwarePage extends ConsumerWidget {
  const HardwarePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final systemState = ref.watch(monitoringControllerProvider).system;
    return ResourceStatusView<SystemResponse>(
      state: systemState,
      onRetry: () =>
          ref.read(monitoringControllerProvider.notifier).fetchSystem(),
      builder: (system) => ListView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg + MediaQuery.paddingOf(context).bottom + 72,
        ),
        children: [
          SectionCard(
            title: 'System Identity',
            child: Column(
              children: [
                InfoRow(label: 'Hostname', value: system.hostname),
                InfoRow(label: 'OS', value: system.os.platform),
                InfoRow(label: 'Kernel', value: system.kernelVersion),
                InfoRow(label: 'Uptime', value: system.uptimeHuman),
                InfoRow(
                  label: 'Chassis Temp',
                  value: formatTemperature(system.chassisTemperatureC),
                  valueColor: toneColor(
                    thresholdTone(system.chassisTemperatureC),
                  ),
                ),
              ],
            ),
          ),
          SectionCard(
            title: 'CPU',
            child: Column(
              children: [
                InfoRow(label: 'Model', value: system.specs.cpu.modelName),
                InfoRow(
                  label: 'Vendor',
                  value: system.specs.cpu.vendor ?? 'N/A',
                ),
                InfoRow(
                  label: 'Architecture',
                  value: system.specs.cpu.architecture,
                ),
                InfoRow(
                  label: 'Physical cores',
                  value: '${system.cpu.physicalCores}',
                ),
                InfoRow(
                  label: 'Logical cores',
                  value: '${system.cpu.logicalCores}',
                ),
                InfoRow(
                  label: 'Current usage',
                  value: '${system.cpu.usagePercent.toStringAsFixed(1)}%',
                  valueColor: toneColor(thresholdTone(system.cpu.usagePercent)),
                ),
                InfoRow(
                  label: 'Temperature',
                  value: formatTemperature(system.cpu.temperatureC),
                  valueColor: toneColor(thresholdTone(system.cpu.temperatureC)),
                ),
                InfoRow(
                  label: 'Min frequency',
                  value: _mhz(system.specs.cpu.minFrequencyMhz),
                ),
                InfoRow(
                  label: 'Max frequency',
                  value: _mhz(system.specs.cpu.maxFrequencyMhz),
                ),
                InfoRow(
                  label: 'Load average',
                  value: _load(system.cpu.loadAverage),
                ),
                InfoRow(
                  label: 'Capabilities',
                  value: system.specs.cpu.capabilities.isEmpty
                      ? 'N/A'
                      : system.specs.cpu.capabilities.take(24).join(', '),
                ),
              ],
            ),
          ),
          SectionCard(
            title: 'Memory',
            child: Column(
              children: [
                InfoRow(
                  label: 'Installed RAM',
                  value: formatBytes(system.memory.total),
                ),
                InfoRow(
                  label: 'Current usage',
                  value: '${system.memory.percent.toStringAsFixed(1)}%',
                  valueColor: toneColor(thresholdTone(system.memory.percent)),
                ),
                InfoRow(
                  label: 'Available RAM',
                  value: formatBytes(system.memory.available),
                ),
                InfoRow(
                  label: 'Memory type',
                  value: system.specs.memory.memoryType ?? 'N/A',
                ),
                InfoRow(
                  label: 'Memory speed',
                  value: _mhz(system.specs.memory.speedMhz),
                ),
                InfoRow(
                  label: 'Swap total',
                  value: formatBytes(system.swap.total),
                ),
                InfoRow(
                  label: 'Swap usage',
                  value: '${system.swap.percent.toStringAsFixed(1)}%',
                  valueColor: toneColor(thresholdTone(system.swap.percent)),
                ),
                for (final module in system.specs.memory.modules)
                  InfoRow(
                    label: module.slot ?? 'Module',
                    value:
                        '${formatBytes(module.sizeBytes)} ${module.memoryType ?? ''} ${_mhz(module.speedMhz)} ${module.manufacturer ?? ''}'
                            .trim(),
                  ),
              ],
            ),
          ),
          SectionCard(
            title: 'Motherboard',
            child: Column(
              children: [
                InfoRow(
                  label: 'Vendor',
                  value: system.specs.motherboard.vendor ?? 'N/A',
                ),
                InfoRow(
                  label: 'Model',
                  value: system.specs.motherboard.model ?? 'N/A',
                ),
                InfoRow(
                  label: 'Version',
                  value: system.specs.motherboard.version ?? 'N/A',
                ),
                InfoRow(
                  label: 'Chipset',
                  value: system.specs.motherboard.chipset ?? 'N/A',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _mhz(num? value) =>
      value == null ? 'N/A' : '${value.toStringAsFixed(0)} MHz';

  String _load(LoadAverage? load) {
    if (load == null) {
      return 'N/A';
    }
    return '${load.oneMin.toStringAsFixed(2)} / ${load.fiveMin.toStringAsFixed(2)} / ${load.fifteenMin.toStringAsFixed(2)}';
  }
}
