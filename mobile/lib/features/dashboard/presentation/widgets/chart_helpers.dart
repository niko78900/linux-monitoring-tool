import 'dart:math' as math;

import 'package:intl/intl.dart';

import '../../../../core/utils/byte_format.dart';

typedef MetricChartValueFormatter = String Function(num? value);

enum MetricChartValueType {
  number,
  percent,
  temperatureC,
  watts,
  bytes,
  bytesPerSecond,
  megabytes,
}

const double metricChartTouchSpotThreshold = 28;
const bool metricChartIncludeMaxTitle = false;

String formatMetricChartValue(num? value, MetricChartValueType type) {
  if (value == null || value.isNaN) {
    return 'N/A';
  }
  return switch (type) {
    MetricChartValueType.number => _trimNumber(value),
    MetricChartValueType.percent => '${_trimNumber(value)}%',
    MetricChartValueType.temperatureC => '${_trimNumber(value)} C',
    MetricChartValueType.watts => '${_trimNumber(value)} W',
    MetricChartValueType.bytes => formatBytes(value),
    MetricChartValueType.bytesPerSecond => formatBytesPerSecond(value),
    MetricChartValueType.megabytes => formatMegabytes(value),
  };
}

String formatMetricChartTimestamp(DateTime? timestamp) {
  if (timestamp == null) {
    return 'N/A';
  }
  return DateFormat.Hms().format(timestamp);
}

String formatMetricChartTooltip(
  DateTime? timestamp,
  num? value,
  MetricChartValueFormatter formatter,
) {
  return '${formatMetricChartTimestamp(timestamp)}\n${formatter(value)}';
}

double metricChartReservedSize(MetricChartValueType type) {
  return switch (type) {
    MetricChartValueType.bytes || MetricChartValueType.bytesPerSecond => 76,
    MetricChartValueType.temperatureC => 54,
    MetricChartValueType.watts => 54,
    MetricChartValueType.percent => 46,
    MetricChartValueType.megabytes => 64,
    MetricChartValueType.number => 48,
  };
}

double metricChartMinimumY(MetricChartValueType type) {
  return switch (type) {
    MetricChartValueType.percent => 10,
    MetricChartValueType.temperatureC => 50,
    MetricChartValueType.watts => 20,
    MetricChartValueType.bytesPerSecond => 1024,
    MetricChartValueType.bytes => 1024,
    MetricChartValueType.megabytes => 1024,
    MetricChartValueType.number => 1,
  };
}

double metricChartEffectiveMaxY(
  Iterable<num?> values, {
  MetricChartValueType valueType = MetricChartValueType.number,
  double? minimumY,
  double? maxY,
}) {
  if (maxY != null) {
    return maxY;
  }

  final floor = minimumY ?? metricChartMinimumY(valueType);
  var observedMax = 0.0;
  for (final value in values) {
    if (value == null || value.isNaN || value.isInfinite) {
      continue;
    }
    if (value > observedMax) {
      observedMax = value.toDouble();
    }
  }

  final paddedMax = observedMax <= 0 ? floor : observedMax * 1.2;
  return metricChartNiceCeiling(math.max(floor, paddedMax));
}

double metricChartNiceCeiling(double value) {
  if (value <= 0 || value.isNaN || value.isInfinite) {
    return 1;
  }
  final magnitude = _pow10(value);
  final normalized = value / magnitude;
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

double metricChartInterval(double maxY) {
  if (maxY <= 0 || maxY.isNaN || maxY.isInfinite) {
    return 1;
  }
  return metricChartNiceCeiling(maxY / 4);
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
