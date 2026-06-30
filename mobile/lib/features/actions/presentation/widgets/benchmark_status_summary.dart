import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/status_tone.dart';
import '../utils/benchmark_ui_state.dart';

class BenchmarkStatusSummary extends StatelessWidget {
  const BenchmarkStatusSummary({
    super.key,
    required this.label,
    required this.message,
    required this.tone,
  });

  final String label;
  final String message;
  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final color = toneColor(tone);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.22)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(benchmarkStateIcon(tone), color: color),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: AppSpacing.xs),
                  Text(message),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
