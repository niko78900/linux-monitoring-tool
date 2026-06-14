import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../dashboard/presentation/widgets/metric_chart.dart';
import '../../domain/models/history_models.dart';

class HistoryChart extends StatefulWidget {
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
    this.windowStart,
    this.windowEnd,
    this.resolutionSeconds,
    this.range,
    @visibleForTesting this.onSelectedSampleChanged,
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
  final DateTime? windowStart;
  final DateTime? windowEnd;
  final int? resolutionSeconds;
  final HistoryRangeValue? range;
  final ValueChanged<int?>? onSelectedSampleChanged;

  @override
  State<HistoryChart> createState() => _HistoryChartState();
}

class _HistoryChartState extends State<HistoryChart> {
  int? _selectedPointIndex;

  @override
  Widget build(BuildContext context) {
    final populated = [
      for (final point in widget.points)
        if (point.value != null) point,
    ];
    if (populated.isEmpty) {
      _selectedPointIndex = null;
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: SizedBox(
            height: 180,
            child: Center(child: Text('${widget.title}: no history data')),
          ),
        ),
      );
    }

    final series = buildMetricChartPlotSeries<HistoryChartPoint>(
      populated,
      timestampOf: (point) => point.timestamp,
      valueOf: (point) => point.value,
      windowStart: _hasValidWindow ? widget.windowStart : null,
      windowEnd: _hasValidWindow ? widget.windowEnd : null,
      maxGap: _gapBreakThreshold,
    );
    if (series.points.isEmpty) {
      _selectedPointIndex = null;
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: SizedBox(
            height: 180,
            child: Center(child: Text('${widget.title}: no history data')),
          ),
        ),
      );
    }
    if (_selectedPointIndex != null &&
        _selectedPointIndex! >= series.points.length) {
      _selectedPointIndex = null;
    }
    final effectiveMaxY = metricChartEffectiveMaxY(
      populated.map((item) => item.value),
      valueType: widget.valueType,
      minimumY: widget.minimumY,
      maxY: widget.maxY,
    );
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
    final selectedSpotIndex = selectedPointIndex == null
        ? null
        : series.spotIndexForPointIndex(selectedPointIndex);
    final barData = LineChartBarData(
      spots: spots,
      isCurved: metricChartUseCurvedTelemetryLines,
      color: widget.color,
      barWidth: 2.4,
      dotData: const FlDotData(show: false),
      showingIndicators: selectedSpotIndex == null
          ? const []
          : [selectedSpotIndex],
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
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              height: 160,
              child: LineChart(
                LineChartData(
                  clipData: const FlClipData.all(),
                  minY: 0,
                  minX: series.minX,
                  maxX: series.maxX,
                  maxY: effectiveMaxY,
                  showingTooltipIndicators: selectedPointIndex == null
                      ? const []
                      : [
                          ShowingTooltipIndicators([
                            LineBarSpot(barData, 0, spots[selectedSpotIndex!]),
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
                              series.pointForSpotIndex(spot.spotIndex)!,
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
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: _hasValidWindow,
                        reservedSize: 28,
                        interval: _bottomTitleInterval(series.maxX),
                        minIncluded: true,
                        maxIncluded: true,
                        getTitlesWidget: (value, meta) {
                          if (!_isBottomTitleValue(value, series.maxX)) {
                            return const SizedBox.shrink();
                          }
                          return SideTitleWidget(
                            meta: meta,
                            space: AppSpacing.xs,
                            child: Text(
                              _formatBottomTitle(value),
                              maxLines: 1,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(color: AppColors.textMuted),
                            ),
                          );
                        },
                      ),
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

  String _tooltipText(
    MetricChartPlotPoint point,
    MetricChartValueFormatter formatter,
  ) {
    return '${formatHistoryChartTooltipTimestamp(point.timestamp, range: widget.range, windowStart: widget.windowStart, windowEnd: widget.windowEnd)}\n${formatter(point.value)}';
  }

  bool get _hasValidWindow {
    final start = widget.windowStart;
    final end = widget.windowEnd;
    return start != null && end != null && end.isAfter(start);
  }

  Duration? get _gapBreakThreshold {
    final seconds = widget.resolutionSeconds;
    if (seconds == null || seconds <= 0) {
      return null;
    }
    return Duration(milliseconds: (seconds * 2500).round());
  }

  double _bottomTitleInterval(double maxX) {
    if (maxX <= 0 || maxX.isNaN || maxX.isInfinite) {
      return 1;
    }
    return maxX / 2;
  }

  bool _isBottomTitleValue(double value, double maxX) {
    final tolerance = maxX <= 0 ? 0.01 : maxX * 0.01;
    final middle = maxX / 2;
    return (value - 0).abs() <= tolerance ||
        (value - middle).abs() <= tolerance ||
        (value - maxX).abs() <= tolerance;
  }

  String _formatBottomTitle(double value) {
    final start = widget.windowStart;
    if (start == null) {
      return '';
    }
    final timestamp = start.add(Duration(milliseconds: (value * 1000).round()));
    return formatHistoryChartAxisTimestamp(timestamp, range: widget.range);
  }
}

@visibleForTesting
String formatHistoryChartTooltipTimestamp(
  DateTime? timestamp, {
  HistoryRangeValue? range,
  DateTime? windowStart,
  DateTime? windowEnd,
}) {
  final includeDate = range == null
      ? _windowNeedsDateContext(windowStart, windowEnd)
      : range != HistoryRangeValue.oneHour;
  return formatMetricChartTimestamp(timestamp, includeDate: includeDate);
}

@visibleForTesting
String formatHistoryChartAxisTimestamp(
  DateTime? timestamp, {
  HistoryRangeValue? range,
}) {
  if (timestamp == null) {
    return 'N/A';
  }
  final local = timestamp.toLocal();
  if (range == HistoryRangeValue.sevenDays ||
      range == HistoryRangeValue.thirtyDays) {
    return DateFormat('MMM d').format(local);
  }
  return DateFormat.Hm().format(local);
}

bool _windowNeedsDateContext(DateTime? start, DateTime? end) {
  if (start == null || end == null || !end.isAfter(start)) {
    return false;
  }
  return end.difference(start) > const Duration(hours: 1);
}
