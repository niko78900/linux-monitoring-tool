// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homelab_tablet/features/dashboard/domain/models/metric_sample.dart';
import 'package:homelab_tablet/features/dashboard/presentation/widgets/metric_chart.dart';
import 'package:homelab_tablet/features/history/domain/models/history_models.dart';
import 'package:homelab_tablet/features/history/presentation/widgets/history_chart.dart';

void main() {
  test('formats metric chart values by unit', () {
    expect(formatMetricChartValue(42, MetricChartValueType.percent), '42%');
    expect(
      formatMetricChartValue(67.4, MetricChartValueType.temperatureC),
      '67.4 C',
    );
    expect(formatMetricChartValue(125, MetricChartValueType.watts), '125 W');
    expect(
      formatMetricChartValue(32 * 1024, MetricChartValueType.bytesPerSecond),
      '32 KB/s',
    );
    expect(formatMetricChartValue(1024, MetricChartValueType.bytes), '1.00 KB');
    expect(
      formatMetricChartValue(512, MetricChartValueType.megabytes),
      '512.0 MB',
    );
  });

  test('metric chart interval handles zero and small values', () {
    expect(metricChartInterval(0), 1);
    expect(metricChartInterval(1), greaterThan(0));
    expect(metricChartInterval(100), 25);
  });

  test('dynamic max expands, respects floors, and rounds to nice values', () {
    expect(
      metricChartEffectiveMaxY([4], valueType: MetricChartValueType.percent),
      10,
    );
    expect(
      metricChartEffectiveMaxY([38], valueType: MetricChartValueType.percent),
      50,
    );
    expect(
      metricChartEffectiveMaxY([82], valueType: MetricChartValueType.percent),
      100,
    );
    expect(
      metricChartEffectiveMaxY([101], valueType: MetricChartValueType.percent),
      200,
    );
    expect(
      metricChartEffectiveMaxY([
        118,
      ], valueType: MetricChartValueType.temperatureC),
      200,
    );
    expect(metricChartNiceCeiling(3.8), 5);
    expect(metricChartNiceCeiling(8.1), 10);
    expect(metricChartNiceCeiling(4100), 5000);
  });

  test('network scaling and formatting stays readable across units', () {
    expect(
      formatMetricChartValue(0, MetricChartValueType.bytesPerSecond),
      '0 B/s',
    );
    expect(
      formatMetricChartValue(824, MetricChartValueType.bytesPerSecond),
      '824 B/s',
    );
    expect(
      formatMetricChartValue(18.4 * 1024, MetricChartValueType.bytesPerSecond),
      '18.4 KB/s',
    );
    expect(
      formatMetricChartValue(
        1.2 * 1024 * 1024,
        MetricChartValueType.bytesPerSecond,
      ),
      '1.2 MB/s',
    );
    expect(
      metricChartEffectiveMaxY([
        4 * 1024 * 1024,
      ], valueType: MetricChartValueType.bytesPerSecond),
      greaterThan(4 * 1024 * 1024),
    );
  });

  test('tooltip and axis edge configuration are stable', () {
    final timestamp = DateTime.utc(2026, 6, 12, 2, 14, 35);
    final timestampText = formatMetricChartTimestamp(timestamp);

    expect(
      formatMetricChartTooltip(
        timestamp,
        25 * 1024,
        (value) =>
            formatMetricChartValue(value, MetricChartValueType.bytesPerSecond),
      ),
      '$timestampText\n25 KB/s',
    );
    expect(metricChartIncludeMaxTitle, isFalse);
    expect(metricChartTouchSpotThreshold, greaterThanOrEqualTo(24));
  });

  test('history tooltip includes date context outside the 1h range', () {
    final timestamp = DateTime(2026, 6, 14, 0, 55);

    final oneHour = formatHistoryChartTooltipTimestamp(
      timestamp,
      range: HistoryRangeValue.oneHour,
    );
    final twentyFourHours = formatHistoryChartTooltipTimestamp(
      timestamp,
      range: HistoryRangeValue.twentyFourHours,
    );

    expect(oneHour, '00:55:00');
    expect(twentyFourHours, contains('Jun 14'));
    expect(twentyFourHours, contains('00:55'));
    expect(twentyFourHours, isNot(matches(RegExp(r'^\d{2}:\d{2}:\d{2}$'))));
  });

  test('sampled telemetry charts use straight line segments by default', () {
    expect(metricChartUseCurvedTelemetryLines, isFalse);
  });

  test('timestamp plot series preserves uneven gaps and one-point ranges', () {
    final start = DateTime.utc(2026, 6, 12, 2);
    final series = buildMetricChartPlotSeries<MetricSample>(
      [
        MetricSample(timestamp: start, value: 1),
        MetricSample(
          timestamp: start.add(const Duration(seconds: 5)),
          value: 2,
        ),
        MetricSample(
          timestamp: start.add(const Duration(minutes: 5, seconds: 5)),
          value: 3,
        ),
      ],
      timestampOf: (sample) => sample.timestamp,
      valueOf: (sample) => sample.value,
    );

    expect(series.points[0].spot.x, 0);
    expect(series.points[1].spot.x, 5);
    expect(series.points[2].spot.x, 305);
    expect(
      series.points[2].spot.x - series.points[1].spot.x,
      greaterThan(series.points[1].spot.x - series.points[0].spot.x),
    );

    final onePoint = buildMetricChartPlotSeries<MetricSample>(
      [MetricSample(timestamp: start, value: 1)],
      timestampOf: (sample) => sample.timestamp,
      valueOf: (sample) => sample.value,
    );
    expect(onePoint.maxX, greaterThan(onePoint.minX));
  });

  test('timestamp plot series handles repeated timestamps and lookup', () {
    final start = DateTime.utc(2026, 6, 12, 2);
    final series = buildMetricChartPlotSeries<MetricSample>(
      [
        MetricSample(timestamp: start, value: 1),
        MetricSample(timestamp: start, value: 2),
        MetricSample(
          timestamp: start.add(const Duration(seconds: 10)),
          value: 3,
        ),
      ],
      timestampOf: (sample) => sample.timestamp,
      valueOf: (sample) => sample.value,
    );

    expect(series.points[1].spot.x, greaterThan(series.points[0].spot.x));
    expect(series.points[2].spot.x, greaterThan(series.points[1].spot.x));
    expect(series.nearestPointIndexForX(0.0009), 1);
    expect(series.nearestPointIndexForX(9), 2);
    expect(series.points[series.nearestPointIndexForX(9)!].sourceIndex, 2);
  });

  test('scale hysteresis expands immediately and contracts later', () {
    final hysteresis = MetricChartScaleHysteresis(contractionSamples: 3);

    expect(hysteresis.update(50), 50);
    expect(hysteresis.update(200), 200);
    expect(hysteresis.update(50), 200);
    expect(hysteresis.update(50), 200);
    expect(hysteresis.update(50), 50);

    final floor = metricChartEffectiveMaxY([
      0,
    ], valueType: MetricChartValueType.percent);
    expect(MetricChartScaleHysteresis().update(floor), 10);
  });

  test('scale hysteresis does not contract without new telemetry updates', () {
    final hysteresis = MetricChartScaleHysteresis(contractionSamples: 3);

    expect(hysteresis.update(200), 200);
    expect(hysteresis.update(50), 200);
    expect(hysteresis.currentMaxY, 200);
    expect(hysteresis.currentMaxY, 200);
    expect(hysteresis.update(50), 200);
    expect(hysteresis.update(50), 50);
  });

  testWidgets('metric chart handles zero, one, and all-zero samples', (
    tester,
  ) async {
    final timestamp = DateTime.utc(2026, 6, 12, 2, 14, 35);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              Expanded(
                child: MetricChart(
                  title: 'One Sample',
                  samples: [MetricSample(timestamp: timestamp, value: 0)],
                  valueType: MetricChartValueType.percent,
                ),
              ),
              Expanded(
                child: MetricChart(
                  title: 'Two Samples',
                  samples: [
                    MetricSample(timestamp: timestamp, value: 0),
                    MetricSample(
                      timestamp: timestamp.add(const Duration(seconds: 1)),
                      value: 0,
                    ),
                  ],
                  valueType: MetricChartValueType.percent,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('One Sample'), findsOneWidget);
    expect(find.text('Two Samples'), findsOneWidget);
  });

  testWidgets('metric chart clips line and fill to all plot edges', (
    tester,
  ) async {
    final timestamp = DateTime.utc(2026, 6, 12, 2);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MetricChart(
            title: 'Receive Throughput',
            samples: [
              MetricSample(timestamp: timestamp, value: 0),
              MetricSample(
                timestamp: timestamp.add(const Duration(seconds: 1)),
                value: 64 * 1024,
              ),
              MetricSample(
                timestamp: timestamp.add(const Duration(seconds: 2)),
                value: 1.2 * 1024 * 1024,
              ),
            ],
            valueType: MetricChartValueType.bytesPerSecond,
          ),
        ),
      ),
    );

    final data = _lineChartData(tester);
    _expectAllSidesClipped(data.clipData);
    final bar = data.lineBarsData.single;
    expect(bar.isCurved, isFalse);
    expect(bar.belowBarData.show, isTrue);
    expect(data.minY, 0);
    expect(bar.spots.first.x, data.minX);
    expect(bar.spots.first.y, data.minY);
    expect(bar.spots.last.x, data.maxX);
    expect(
      bar.spots.map((spot) => spot.y).reduce((a, b) => a > b ? a : b),
      lessThanOrEqualTo(data.maxY),
    );
  });

  testWidgets('metric chart keeps sparse and repeated timestamp data clipped', (
    tester,
  ) async {
    final timestamp = DateTime.utc(2026, 6, 12, 2);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MetricChart(
            title: 'GPU Power',
            samples: [
              MetricSample(timestamp: timestamp, value: 10),
              MetricSample(timestamp: timestamp, value: 40),
              MetricSample(
                timestamp: timestamp.add(const Duration(milliseconds: 1)),
                value: 0,
              ),
            ],
            valueType: MetricChartValueType.watts,
          ),
        ),
      ),
    );

    final data = _lineChartData(tester);
    _expectAllSidesClipped(data.clipData);
    expect(data.lineBarsData.single.isCurved, isFalse);
    expect(
      data.lineBarsData.single.spots[1].x,
      greaterThan(data.lineBarsData.single.spots[0].x),
    );
    expect(data.lineBarsData.single.spots.last.y, data.minY);
  });

  testWidgets('metric chart keeps nearest-X selection during vertical drag', (
    tester,
  ) async {
    final selected = <int?>[];
    final timestamp = DateTime.utc(2026, 6, 12, 2);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MetricChart(
            title: 'Drag Chart',
            samples: [
              MetricSample(timestamp: timestamp, value: 10),
              MetricSample(
                timestamp: timestamp.add(const Duration(seconds: 10)),
                value: 30,
              ),
              MetricSample(
                timestamp: timestamp.add(const Duration(seconds: 20)),
                value: 20,
              ),
            ],
            valueType: MetricChartValueType.percent,
            onSelectedSampleChanged: selected.add,
          ),
        ),
      ),
    );

    final chartRect = tester.getRect(find.byType(LineChart));
    final gesture = await tester.startGesture(
      Offset(chartRect.left + 64, chartRect.center.dy + 32),
    );
    await tester.pump();
    await gesture.moveTo(
      Offset(chartRect.right - 20, chartRect.center.dy - 54),
    );
    await tester.pump();

    expect(selected.whereType<int>(), isNotEmpty);
    expect(selected.whereType<int>().last, 2);
    expect(selected.take(selected.length - 1), isNot(contains(null)));

    await gesture.up();
  });

  testWidgets('history chart uses shared sparse-data chart behavior', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HistoryChart(
            title: 'History Network',
            valueType: MetricChartValueType.bytesPerSecond,
            points: [
              HistoryChartPoint(
                timestamp: DateTime.utc(2026, 6, 12, 2, 14, 35),
                value: 0,
              ),
              HistoryChartPoint(
                timestamp: DateTime.utc(2026, 6, 12, 2, 14, 40),
                value: 1024,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('History Network'), findsOneWidget);
    final data = _lineChartData(tester);
    _expectAllSidesClipped(data.clipData);
    expect(data.lineBarsData.single.isCurved, isFalse);
    expect(data.lineBarsData.single.belowBarData.show, isTrue);
  });

  testWidgets('history chart clips newest spikes at the right edge', (
    tester,
  ) async {
    final timestamp = DateTime.utc(2026, 6, 12, 2);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HistoryChart(
            title: 'History Network Send',
            valueType: MetricChartValueType.bytesPerSecond,
            points: [
              HistoryChartPoint(timestamp: timestamp, value: 0),
              HistoryChartPoint(
                timestamp: timestamp.add(const Duration(seconds: 1)),
                value: 512,
              ),
              HistoryChartPoint(
                timestamp: timestamp.add(const Duration(seconds: 2)),
                value: 5 * 1024 * 1024,
              ),
            ],
          ),
        ),
      ),
    );

    final data = _lineChartData(tester);
    _expectAllSidesClipped(data.clipData);
    final bar = data.lineBarsData.single;
    expect(bar.isCurved, isFalse);
    expect(bar.spots.last.x, data.maxX);
    expect(bar.spots.last.y, lessThanOrEqualTo(data.maxY));
  });

  testWidgets('history chart anchors x range to backend history window', (
    tester,
  ) async {
    final start = DateTime(2026, 6, 14);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HistoryChart(
            title: 'Anchored History',
            valueType: MetricChartValueType.percent,
            windowStart: start,
            windowEnd: start.add(const Duration(hours: 24)),
            resolutionSeconds: 300,
            range: HistoryRangeValue.twentyFourHours,
            points: [
              HistoryChartPoint(
                timestamp: start.add(const Duration(hours: 6)),
                value: 10,
              ),
              HistoryChartPoint(
                timestamp: start.add(const Duration(hours: 12)),
                value: 20,
              ),
            ],
          ),
        ),
      ),
    );

    final data = _lineChartData(tester);
    final bar = data.lineBarsData.single;
    expect(data.minX, 0);
    expect(data.maxX, 86400);
    expect(bar.spots.first.x, 21600);
    expect(bar.spots.last.x, 43200);
  });

  testWidgets('history chart breaks long gaps instead of connecting them', (
    tester,
  ) async {
    final start = DateTime(2026, 6, 14);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HistoryChart(
            title: 'Gapped History',
            valueType: MetricChartValueType.percent,
            windowStart: start,
            windowEnd: start.add(const Duration(hours: 2)),
            resolutionSeconds: 300,
            range: HistoryRangeValue.twentyFourHours,
            points: [
              HistoryChartPoint(timestamp: start, value: 10),
              HistoryChartPoint(
                timestamp: start.add(const Duration(minutes: 5)),
                value: 20,
              ),
              HistoryChartPoint(
                timestamp: start.add(const Duration(hours: 1, minutes: 5)),
                value: 30,
              ),
            ],
          ),
        ),
      ),
    );

    final data = _lineChartData(tester);
    final spots = data.lineBarsData.single.spots;
    expect(spots, contains(FlSpot.nullSpot));
    expect(spots.where((spot) => spot != FlSpot.nullSpot), hasLength(3));
  });

  testWidgets('history chart keeps nearest-X selection during vertical drag', (
    tester,
  ) async {
    final selected = <int?>[];
    final timestamp = DateTime.utc(2026, 6, 12, 2);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HistoryChart(
            title: 'History Drag',
            valueType: MetricChartValueType.percent,
            onSelectedSampleChanged: selected.add,
            points: [
              HistoryChartPoint(timestamp: timestamp, value: 10),
              HistoryChartPoint(
                timestamp: timestamp.add(const Duration(seconds: 10)),
                value: 30,
              ),
              HistoryChartPoint(
                timestamp: timestamp.add(const Duration(seconds: 20)),
                value: 20,
              ),
            ],
          ),
        ),
      ),
    );

    final chartRect = tester.getRect(find.byType(LineChart));
    final gesture = await tester.startGesture(
      Offset(chartRect.left + 64, chartRect.center.dy + 32),
    );
    await tester.pump();
    await gesture.moveTo(
      Offset(chartRect.right - 20, chartRect.center.dy - 54),
    );
    await tester.pump();

    expect(selected.whereType<int>(), isNotEmpty);
    expect(selected.whereType<int>().last, 2);
    expect(selected.take(selected.length - 1), isNot(contains(null)));

    await gesture.up();
  });
}

LineChartData _lineChartData(WidgetTester tester) {
  return tester.widget<LineChart>(find.byType(LineChart)).data;
}

void _expectAllSidesClipped(FlClipData clipData) {
  expect(clipData, const FlClipData.all());
  expect(clipData.top, isTrue);
  expect(clipData.bottom, isTrue);
  expect(clipData.left, isTrue);
  expect(clipData.right, isTrue);
}
