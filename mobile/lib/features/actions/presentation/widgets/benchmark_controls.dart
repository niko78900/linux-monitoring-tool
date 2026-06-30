import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/section_card.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../domain/models/benchmark_models.dart';
import '../utils/benchmark_ui_state.dart';
import 'benchmark_details.dart';
import 'benchmark_result_summary.dart';
import 'benchmark_status_summary.dart';

class BenchmarkControls extends StatelessWidget {
  const BenchmarkControls({
    super.key,
    required this.status,
    required this.notice,
    required this.busy,
    required this.dateFormat,
    required this.onCpuSelected,
    required this.onGpuSelected,
    required this.onStop,
    required this.onRefresh,
  });

  final BenchmarkStatus? status;
  final BenchmarkNotice? notice;
  final bool busy;
  final DateFormat dateFormat;
  final ValueChanged<BenchmarkKind> onCpuSelected;
  final VoidCallback onGpuSelected;
  final VoidCallback onStop;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final uiState = benchmarkUiState(status, notice);
    final running = uiState == BenchmarkUiState.running;
    final controlsBlocked = benchmarkServiceBlocked(uiState);
    final startEnabled = !busy && !running && !controlsBlocked;
    final label = status?.label ?? 'No active benchmark';
    final rawDetail = benchmarkRawDetail(status, notice);
    final hasDetails = hasBenchmarkDetails(status, rawDetail);
    return SectionCard(
      title: 'Benchmarks',
      trailing: StatusBadge(
        label: benchmarkStateLabel(uiState),
        tone: benchmarkTone(uiState),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Run allowlisted CPU and GPU tests through the control agent. '
            'Only one benchmark can run at a time.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.md),
          BenchmarkStatusSummary(
            label: label,
            message: notice?.message ?? benchmarkDefaultMessage(uiState),
            tone: benchmarkTone(uiState),
          ),
          if (status != null) ...[
            const SizedBox(height: AppSpacing.md),
            BenchmarkMetadata(status: status!, dateFormat: dateFormat),
          ],
          if (status?.result.isNotEmpty ?? false) ...[
            const SizedBox(height: AppSpacing.md),
            BenchmarkResultSummary(status: status!),
          ],
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              PopupMenuButton<BenchmarkKind>(
                enabled: startEnabled,
                onSelected: onCpuSelected,
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: BenchmarkKind.cpuSingle,
                    child: Text('Single-Core Benchmark'),
                  ),
                  PopupMenuItem(
                    value: BenchmarkKind.cpuMulti,
                    child: Text('Multi-Core Benchmark'),
                  ),
                  PopupMenuItem(
                    value: BenchmarkKind.cpuStress,
                    child: Text('CPU Stress Test'),
                  ),
                ],
                child: _BenchmarkMenuButton(
                  icon: Icons.memory,
                  label: busy ? 'Working...' : 'CPU Benchmark',
                  enabled: startEnabled,
                ),
              ),
              FilledButton.icon(
                onPressed: startEnabled ? onGpuSelected : null,
                icon: const Icon(Icons.speed),
                label: const Text('GPU Vulkan Benchmark'),
              ),
              if (running)
                OutlinedButton.icon(
                  onPressed: busy ? null : onStop,
                  icon: const Icon(Icons.stop_circle),
                  label: const Text('Stop Running Test'),
                ),
              OutlinedButton.icon(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh status'),
              ),
            ],
          ),
          if (hasDetails) ...[
            const SizedBox(height: AppSpacing.md),
            BenchmarkDetails(status: status, rawDetail: rawDetail),
          ],
        ],
      ),
    );
  }
}

class _BenchmarkMenuButton extends StatelessWidget {
  const _BenchmarkMenuButton({
    required this.icon,
    required this.label,
    required this.enabled,
  });

  final IconData icon;
  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final foreground = enabled
        ? Theme.of(context).colorScheme.onPrimary
        : Theme.of(context).disabledColor;
    final background = enabled
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).disabledColor.withValues(alpha: 0.12);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: foreground),
            const SizedBox(width: AppSpacing.sm),
            Text(label, style: TextStyle(color: foreground)),
            const SizedBox(width: AppSpacing.xs),
            Icon(Icons.arrow_drop_down, color: foreground),
          ],
        ),
      ),
    );
  }
}
