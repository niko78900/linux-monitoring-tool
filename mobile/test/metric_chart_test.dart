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

    expect(
      formatMetricChartTooltip(
        timestamp,
        25 * 1024,
        (value) =>
            formatMetricChartValue(value, MetricChartValueType.bytesPerSecond),
      ),
      '02:14:35\n25 KB/s',
    );
    expect(metricChartIncludeMaxTitle, isFalse);
    expect(metricChartTouchSpotThreshold, greaterThanOrEqualTo(24));
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
  });
}
