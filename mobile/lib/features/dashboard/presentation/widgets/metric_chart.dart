import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/byte_format.dart';
import '../../domain/models/metric_sample.dart';

typedef MetricChartValueFormatter = String Function(num? value);

enum MetricChartValueType {
  number,
  percent,
  temperatureC,
  watts,
  bytesPerSecond,
}

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
  });

  final String title;
  final List<MetricSample> samples;
  final double? maxY;
  final Color color;
  final MetricChartValueType valueType;
  final MetricChartValueFormatter? valueFormatter;
  final MetricChartValueFormatter? tooltipValueFormatter;
  final double? leftReservedSize;

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

    final effectiveMaxY =
        maxY ?? (calculatedMax <= 0 ? 1 : calculatedMax * 1.15);
    final horizontalInterval = metricChartInterval(effectiveMaxY);
    final axisFormatter =
        valueFormatter ?? (value) => formatMetricChartValue(value, valueType);
    final tooltipFormatter =
        tooltipValueFormatter ??
        valueFormatter ??
        (value) => formatMetricChartValue(value, valueType);
    final reservedSize = leftReservedSize ?? metricChartReservedSize(valueType);
    final timestampFormatter = DateFormat.Hms();

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
                  maxY: effectiveMaxY,
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      fitInsideHorizontally: true,
                      fitInsideVertically: true,
                      getTooltipItems: (spots) => [
                        for (final spot in spots)
                          LineTooltipItem(
                            _tooltipText(
                              spot,
                              timestampFormatter,
                              tooltipFormatter,
                            ),
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
    DateFormat timestampFormatter,
    MetricChartValueFormatter formatter,
  ) {
    final index = spot.x.round().clamp(0, samples.length - 1);
    final timestamp = timestampFormatter.format(samples[index].timestamp);
    return '$timestamp\n${formatter(spot.y)}';
  }
}

String formatMetricChartValue(num? value, MetricChartValueType type) {
  if (value == null || value.isNaN) {
    return 'N/A';
  }
  return switch (type) {
    MetricChartValueType.number => _trimNumber(value),
    MetricChartValueType.percent => '${_trimNumber(value)}%',
    MetricChartValueType.temperatureC => '${_trimNumber(value)} C',
    MetricChartValueType.watts => '${_trimNumber(value)} W',
    MetricChartValueType.bytesPerSecond => formatBytesPerSecond(value),
  };
}

double metricChartReservedSize(MetricChartValueType type) {
  return switch (type) {
    MetricChartValueType.bytesPerSecond => 72,
    MetricChartValueType.temperatureC => 54,
    MetricChartValueType.watts => 54,
    MetricChartValueType.percent => 46,
    MetricChartValueType.number => 48,
  };
}

double metricChartInterval(double maxY) {
  if (maxY <= 0) {
    return 1;
  }
  final raw = maxY / 4;
  final magnitude = _pow10(raw);
  final normalized = raw / magnitude;
  final nice = normalized <= 1
      ? 1
      : normalized <= 2
      ? 2
      : normalized <= 2.5
      ? 2.5
      : normalized <= 5
      ? 5
      : 10;
  return nice * magnitude;
}

String _trimNumber(num value) {
  if ((value - value.round()).abs() < 0.05) {
    return value.round().toString();
  }
  return value.toStringAsFixed(1);
}

double _pow10(double value) {
  var magnitude = 1.0;
  if (value >= 1) {
    while (value / magnitude >= 10) {
      magnitude *= 10;
    }
  } else {
    while (value / magnitude < 1) {
      magnitude /= 10;
    }
  }
  return magnitude;
}
