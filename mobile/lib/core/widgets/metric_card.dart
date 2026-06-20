import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'status_tone.dart';

class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.title,
    required this.value,
    this.subtitle,
    this.tone = StatusTone.neutral,
    this.icon,
    this.progress,
    this.progressColor,
    this.maxValueLines = 1,
    this.valueOverflow = TextOverflow.ellipsis,
    this.onTap,
  });

  final String title;
  final String value;
  final String? subtitle;
  final StatusTone tone;
  final IconData? icon;
  final double? progress;
  final Color? progressColor;
  final int maxValueLines;
  final TextOverflow valueOverflow;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = toneColor(tone);
    final barColor = progressColor ?? color;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, color: color, size: 20),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                  Expanded(
                    child: Text(
                      title,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                value,
                maxLines: maxValueLines,
                overflow: valueOverflow,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  subtitle!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
                ),
              ],
              if (progress != null) ...[
                const SizedBox(height: AppSpacing.md),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    minHeight: 6,
                    value: progress!.clamp(0, 100) / 100,
                    color: barColor,
                    backgroundColor: barColor.withValues(alpha: 0.14),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
