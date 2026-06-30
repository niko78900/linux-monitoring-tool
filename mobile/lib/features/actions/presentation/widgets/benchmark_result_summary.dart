import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../domain/models/benchmark_models.dart';
import '../utils/benchmark_ui_state.dart';

class BenchmarkMetadata extends StatelessWidget {
  const BenchmarkMetadata({
    super.key,
    required this.status,
    required this.dateFormat,
  });

  final BenchmarkStatus status;
  final DateFormat dateFormat;

  @override
  Widget build(BuildContext context) {
    final chips = [
      BenchmarkInfoPill(label: 'Server cores', value: status.nproc.toString()),
      if (status.startedAt != null)
        BenchmarkInfoPill(
          label: 'Started',
          value: dateFormat.format(status.startedAt!.toLocal()),
        ),
      if (status.finishedAt != null)
        BenchmarkInfoPill(
          label: 'Finished',
          value: dateFormat.format(status.finishedAt!.toLocal()),
        ),
      if (status.durationSeconds != null)
        BenchmarkInfoPill(
          label: 'Duration',
          value: '${status.durationSeconds}s',
        ),
      if (status.threads != null)
        BenchmarkInfoPill(label: 'Threads', value: status.threads.toString()),
      if (status.workers != null)
        BenchmarkInfoPill(label: 'Workers', value: status.workers.toString()),
    ];
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: chips,
    );
  }
}

class BenchmarkResultSummary extends StatelessWidget {
  const BenchmarkResultSummary({super.key, required this.status});

  final BenchmarkStatus status;

  @override
  Widget build(BuildContext context) {
    final entries = benchmarkResultEntries(status);
    if (entries.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Results', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: entries
              .map(
                (entry) =>
                    BenchmarkInfoPill(label: entry.label, value: entry.value),
              )
              .toList(growable: false),
        ),
      ],
    );
  }
}

class BenchmarkInfoPill extends StatelessWidget {
  const BenchmarkInfoPill({
    super.key,
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text('$label: $value'),
      visualDensity: VisualDensity.compact,
    );
  }
}
