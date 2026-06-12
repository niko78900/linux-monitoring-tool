import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../dashboard/presentation/widgets/metric_chart.dart';
import '../../domain/models/history_models.dart';

class HistoryChart extends StatelessWidget {
  const HistoryChart({
    super.key,
    required this.title,
    required this.points,
    this.color = AppColors.accent,
    this.maxY,
    this.valueType = MetricChartValueType.number,
    this.valueFormatter,
    this.tooltipValueFormatter,
    this.leftReservedSize,
    this.minimumY,
  });

  final String title;
  final List<HistoryChartPoint> points;
  final Color color;
  final double? maxY;
  final MetricChartValueType valueType;
  final MetricChartValueFormatter? valueFormatter;
  final MetricChartValueFormatter? tooltipValueFormatter;
  final double? leftReservedSize;
  final double? minimumY;

  @override
  Widget build(BuildContext context) {
    final populated = [
      for (final point in points)
        if (point.value != null) point,
    ];
    if (populated.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: SizedBox(
            height: 180,
            child: Center(child: Text('$title: no history data')),
          ),
        ),
      );
    }

    final spots = <FlSpot>[
      for (var index = 0; index < populated.length; index += 1)
        FlSpot(index.toDouble(), populated[index].value!),
    ];
    final effectiveMaxY = metricChartEffectiveMaxY(
      populated.map((item) => item.value),
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
            const SizedBox(height: AppSpacing.md),
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
                            _tooltipText(spot, tooltipFormatter, populated),
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

  String _tooltipText(
    FlSpot spot,
    MetricChartValueFormatter formatter,
    List<HistoryChartPoint> populated,
  ) {
    final index = spot.x.round().clamp(0, populated.length - 1);
    final point = populated[index];
    return formatMetricChartTooltip(point.timestamp, point.value, formatter);
  }
}
