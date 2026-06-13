import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/models/metric_sample.dart';
export 'chart_helpers.dart';

import 'chart_helpers.dart';

class MetricChart extends StatefulWidget {
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
    @visibleForTesting this.onSelectedSampleChanged,
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
  final ValueChanged<int?>? onSelectedSampleChanged;

  @override
  State<MetricChart> createState() => _MetricChartState();
}

class _MetricChartState extends State<MetricChart> {
  final MetricChartScaleHysteresis _scaleHysteresis =
      MetricChartScaleHysteresis();
  int? _selectedPointIndex;
  String? _lastTelemetrySignature;

  @override
  void didUpdateWidget(covariant MetricChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.title != widget.title ||
        oldWidget.valueType != widget.valueType ||
        oldWidget.minimumY != widget.minimumY ||
        oldWidget.maxY != widget.maxY) {
      _scaleHysteresis.reset();
      _lastTelemetrySignature = null;
      _selectedPointIndex = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.samples.isEmpty) {
      _scaleHysteresis.reset();
      _lastTelemetrySignature = null;
      _selectedPointIndex = null;
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: SizedBox(
            height: 180,
            child: Center(child: Text('${widget.title}: waiting for samples')),
          ),
        ),
      );
    }
    final series = buildMetricChartPlotSeries<MetricSample>(
      widget.samples,
      timestampOf: (sample) => sample.timestamp,
      valueOf: (sample) => sample.value,
    );
    if (series.points.isEmpty) {
      _scaleHysteresis.reset();
      _lastTelemetrySignature = null;
      _selectedPointIndex = null;
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: SizedBox(
            height: 180,
            child: Center(child: Text('${widget.title}: waiting for samples')),
          ),
        ),
      );
    }

    if (_selectedPointIndex != null &&
        _selectedPointIndex! >= series.points.length) {
      _selectedPointIndex = null;
    }

    final targetMaxY = metricChartEffectiveMaxY(
      series.points.map((item) => item.value),
      valueType: widget.valueType,
      minimumY: widget.minimumY,
      maxY: widget.maxY,
    );
    final telemetrySignature = _telemetrySignature(series, targetMaxY);
    final effectiveMaxY = widget.maxY == null
        ? _effectiveMaxYForTelemetry(telemetrySignature, targetMaxY)
        : targetMaxY;
    final horizontalInterval = metricChartInterval(effectiveMaxY);
    final axisFormatter =
        widget.valueFormatter ??
        (value) => formatMetricChartValue(value, widget.valueType);
    final tooltipFormatter =
        widget.tooltipValueFormatter ??
        widget.valueFormatter ??
        (value) => formatMetricChartValue(value, widget.valueType);
    final reservedSize =
        widget.leftReservedSize ?? metricChartReservedSize(widget.valueType);
    final selectedPointIndex = _selectedPointIndex;
    final spots = series.spots;
    final barData = LineChartBarData(
      spots: spots,
      isCurved: true,
      color: widget.color,
      barWidth: 2.4,
      dotData: const FlDotData(show: false),
      showingIndicators: selectedPointIndex == null
          ? const []
          : [selectedPointIndex],
      belowBarData: BarAreaData(
        show: true,
        color: widget.color.withValues(alpha: 0.12),
      ),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              height: 160,
              child: LineChart(
                LineChartData(
                  minY: 0,
                  minX: series.minX,
                  maxX: series.maxX,
                  maxY: effectiveMaxY,
                  showingTooltipIndicators: selectedPointIndex == null
                      ? const []
                      : [
                          ShowingTooltipIndicators([
                            LineBarSpot(barData, 0, spots[selectedPointIndex]),
                          ]),
                        ],
                  lineTouchData: LineTouchData(
                    handleBuiltInTouches: false,
                    touchCallback: (event, response) =>
                        _handleTouch(event, response, series),
                    touchSpotThreshold: metricChartTouchSpotThreshold,
                    getTouchedSpotIndicator: (barData, spotIndexes) =>
                        spotIndexes
                            .map(
                              (_) => TouchedSpotIndicatorData(
                                FlLine(
                                  color: widget.color.withValues(alpha: 0.35),
                                  strokeWidth: 1,
                                ),
                                FlDotData(
                                  show: true,
                                  getDotPainter:
                                      (spot, percent, barData, index) =>
                                          FlDotCirclePainter(
                                            radius: 4,
                                            color: widget.color,
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
                            _tooltipText(
                              series.points[spot.spotIndex],
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
                  lineBarsData: [barData],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleTouch(
    FlTouchEvent event,
    LineTouchResponse? response,
    MetricChartPlotSeries series,
  ) {
    if (!event.isInterestedForInteractions || response == null) {
      _selectPoint(null);
      return;
    }

    final index = series.nearestPointIndexForX(
      response.touchChartCoordinate.dx,
    );
    _selectPoint(index);
  }

  void _selectPoint(int? index) {
    if (_selectedPointIndex == index) {
      return;
    }
    setState(() {
      _selectedPointIndex = index;
    });
    widget.onSelectedSampleChanged?.call(index);
  }

  double _effectiveMaxYForTelemetry(String signature, double targetMaxY) {
    if (_lastTelemetrySignature != signature) {
      _lastTelemetrySignature = signature;
      return _scaleHysteresis.update(targetMaxY);
    }
    return _scaleHysteresis.currentMaxY ?? targetMaxY;
  }

  String _telemetrySignature(MetricChartPlotSeries series, double targetMaxY) {
    final last = series.points.last;
    return '${series.points.length}:'
        '${last.timestamp?.microsecondsSinceEpoch ?? last.spot.x}:'
        '$targetMaxY';
  }

  String _tooltipText(
    MetricChartPlotPoint point,
    MetricChartValueFormatter formatter,
  ) {
    return formatMetricChartTooltip(point.timestamp, point.value, formatter);
  }
}
