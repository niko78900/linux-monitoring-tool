import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/models/metric_sample.dart';

class MetricChart extends StatelessWidget {
  const MetricChart({
    super.key,
    required this.title,
    required this.samples,
    this.maxY,
    this.color = AppColors.accent,
  });

  final String title;
  final List<MetricSample> samples;
  final double? maxY;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (samples.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: SizedBox(
            height: 180,
            child: Center(child: Text('$title: waiting for samples')),
          ),
        ),
      );
    }
    final spots = <FlSpot>[
      for (var index = 0; index < samples.length; index += 1)
        FlSpot(index.toDouble(), samples[index].value),
    ];
    final calculatedMax = samples
        .map((item) => item.value)
        .fold<double>(0, (previous, item) => item > previous ? item : previous);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              height: 160,
              child: LineChart(
                LineChartData(
                  minY: 0,
                  maxY: maxY ?? (calculatedMax <= 0 ? 1 : calculatedMax * 1.15),
                  gridData: FlGridData(
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (value) =>
                        FlLine(color: AppColors.border, strokeWidth: 1),
                  ),
                  titlesData: const FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 36,
                      ),
                    ),
                    rightTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      color: color,
                      barWidth: 2.4,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        color: color.withValues(alpha: 0.12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
