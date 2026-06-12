import 'package:flutter_test/flutter_test.dart';
import 'package:homelab_tablet/features/dashboard/presentation/widgets/metric_chart.dart';

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
  });

  test('metric chart interval handles zero and small values', () {
    expect(metricChartInterval(0), 1);
    expect(metricChartInterval(1), greaterThan(0));
    expect(metricChartInterval(100), 25);
  });
}
