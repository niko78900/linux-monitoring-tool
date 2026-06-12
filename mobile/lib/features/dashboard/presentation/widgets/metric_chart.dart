import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/models/metric_sample.dart';
export 'chart_helpers.dart';

import 'chart_helpers.dart';

class MetricChart extends StatelessWidget {
  const MetricChart({
    super.key,
    required this.title,
    required this.samples,
    this.maxY,
    this.color = AppColors.accent,
    this.valueType = MetricChartValueType.number,
    this.valueFormatter,
    this.tooltipValueFormatter,
    this.leftReservedSize,
    this.minimumY,
  });

  final String title;
  final List<MetricSample> samples;
  final double? maxY;
  final Color color;
  final MetricChartValueType valueType;
  final MetricChartValueFormatter? valueFormatter;
  final MetricChartValueFormatter? tooltipValueFormatter;
  final double? leftReservedSize;
  final double? minimumY;

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
    final effectiveMaxY = metricChartEffectiveMaxY(
      samples.map((item) => item.value),
      valueType: valueType,
      minimumY: minimumY,
      maxY: maxY,
    );
    final horizontalInterval = metricChartInterval(effectiveMaxY);
    final axisFormatter =
        valueFormatter ?? (value) => formatMetricChartValue(value, valueType);
    final tooltipFormatter =
        tooltipValueFormatter ??
        valueFormatter ??
        (value) => formatMetricChartValue(value, valueType);
    final reservedSize = leftReservedSize ?? metricChartReservedSize(valueType);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              height: 160,
              child: LineChart(
                LineChartData(
                  minY: 0,
                  minX: 0,
                  maxX: spots.length > 1 ? (spots.length - 1).toDouble() : 1,
                  maxY: effectiveMaxY,
                  lineTouchData: LineTouchData(
                    handleBuiltInTouches: true,
                    touchSpotThreshold: metricChartTouchSpotThreshold,
                    getTouchedSpotIndicator: (barData, spotIndexes) =>
                        spotIndexes
                            .map(
                              (_) => TouchedSpotIndicatorData(
                                FlLine(
                                  color: color.withValues(alpha: 0.35),
                                  strokeWidth: 1,
                                ),
                                FlDotData(
                                  show: true,
                                  getDotPainter:
                                      (spot, percent, barData, index) =>
                                          FlDotCirclePainter(
                                            radius: 4,
                                            color: color,
                                            strokeWidth: 2,
                                            strokeColor: AppColors.surface,
                                          ),
                                ),
                              ),
                            )
                            .toList(growable: false),
                    touchTooltipData: LineTouchTooltipData(
                      fitInsideHorizontally: true,
                      fitInsideVertically: true,
                      getTooltipItems: (spots) => [
                        for (final spot in spots)
                          LineTooltipItem(
                            _tooltipText(spot, tooltipFormatter),
                            const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                  gridData: FlGridData(
                    drawVerticalLine: false,
                    horizontalInterval: horizontalInterval,
                    getDrawingHorizontalLine: (value) =>
                        FlLine(color: AppColors.border, strokeWidth: 1),
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: reservedSize,
                        interval: horizontalInterval,
                        minIncluded: true,
                        maxIncluded: metricChartIncludeMaxTitle,
                        getTitlesWidget: (value, meta) {
                          return SideTitleWidget(
                            meta: meta,
                            space: AppSpacing.xs,
                            child: Text(
                              axisFormatter(value),
                              maxLines: 1,
                              textAlign: TextAlign.right,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(color: AppColors.textMuted),
                            ),
                          );
                        },
                      ),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: const AxisTitles(
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

  String _tooltipText(FlSpot spot, MetricChartValueFormatter formatter) {
    final index = spot.x.round().clamp(0, samples.length - 1);
    return formatMetricChartTooltip(
      samples[index].timestamp,
      samples[index].value,
      formatter,
    );
  }
}
