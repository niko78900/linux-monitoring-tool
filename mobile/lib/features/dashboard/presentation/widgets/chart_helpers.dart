import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
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
const bool metricChartUseCurvedTelemetryLines = false;
const double _repeatedTimestampStepSeconds = 0.001;

class MetricChartPlotPoint {
  const MetricChartPlotPoint({
    required this.spot,
    required this.timestamp,
    required this.value,
    required this.sourceIndex,
  });

  final FlSpot spot;
  final DateTime? timestamp;
  final double value;
  final int sourceIndex;
}

class MetricChartPlotSeries {
  const MetricChartPlotSeries(
    this.points, {
    List<FlSpot>? spots,
    List<int>? pointSpotIndexes,
    double? minX,
    double? maxX,
  }) : _spots = spots,
       _pointSpotIndexes = pointSpotIndexes,
       _minX = minX,
       _maxX = maxX;

  final List<MetricChartPlotPoint> points;
  final List<FlSpot>? _spots;
  final List<int>? _pointSpotIndexes;
  final double? _minX;
  final double? _maxX;

  List<FlSpot> get spots => _spots ?? [for (final point in points) point.spot];

  double get minX => _minX ?? (points.isEmpty ? 0 : points.first.spot.x);

  double get maxX {
    if (_maxX != null) {
      return _maxX > minX ? _maxX : minX + 1;
    }
    if (points.isEmpty) {
      return 1;
    }
    final first = points.first.spot.x;
    final last = points.last.spot.x;
    return last > first ? last : first + 1;
  }

  int spotIndexForPointIndex(int pointIndex) {
    return _pointSpotIndexes?[pointIndex] ?? pointIndex;
  }

  MetricChartPlotPoint? pointForSpotIndex(int spotIndex) {
    final indexes = _pointSpotIndexes;
    if (indexes == null) {
      if (spotIndex < 0 || spotIndex >= points.length) {
        return null;
      }
      return points[spotIndex];
    }
    final pointIndex = indexes.indexOf(spotIndex);
    if (pointIndex < 0 || pointIndex >= points.length) {
      return null;
    }
    return points[pointIndex];
  }

  int? nearestPointIndexForX(double x) {
    if (points.isEmpty) {
      return null;
    }
    var selectedIndex = 0;
    var selectedDistance = (points.first.spot.x - x).abs();
    for (var index = 1; index < points.length; index += 1) {
      final distance = (points[index].spot.x - x).abs();
      if (distance < selectedDistance) {
        selectedIndex = index;
        selectedDistance = distance;
      }
    }
    return selectedIndex;
  }
}

class MetricChartScaleHysteresis {
  MetricChartScaleHysteresis({this.contractionSamples = 4});

  final int contractionSamples;
  double? _effectiveMaxY;
  double? _lowerTargetY;
  int _lowerSampleCount = 0;

  double? get currentMaxY => _effectiveMaxY;

  double update(double targetMaxY) {
    final previous = _effectiveMaxY;
    if (previous == null || targetMaxY >= previous) {
      _effectiveMaxY = targetMaxY;
      _lowerTargetY = null;
      _lowerSampleCount = 0;
      return targetMaxY;
    }

    if (_lowerTargetY != targetMaxY) {
      _lowerTargetY = targetMaxY;
      _lowerSampleCount = 1;
      return previous;
    }

    _lowerSampleCount += 1;
    if (_lowerSampleCount < contractionSamples) {
      return previous;
    }

    _effectiveMaxY = targetMaxY;
    _lowerTargetY = null;
    _lowerSampleCount = 0;
    return targetMaxY;
  }

  void reset() {
    _effectiveMaxY = null;
    _lowerTargetY = null;
    _lowerSampleCount = 0;
  }
}

MetricChartPlotSeries buildMetricChartPlotSeries<T>(
  List<T> items, {
  required DateTime? Function(T item) timestampOf,
  required double? Function(T item) valueOf,
  DateTime? windowStart,
  DateTime? windowEnd,
  Duration? maxGap,
}) {
  final points = <MetricChartPlotPoint>[];
  final spots = <FlSpot>[];
  final pointSpotIndexes = <int>[];
  DateTime? firstTimestamp;
  DateTime? previousTimestamp;
  final hasWindow =
      windowStart != null &&
      windowEnd != null &&
      windowEnd.isAfter(windowStart);
  final maxX = hasWindow
      ? windowEnd.difference(windowStart).inMilliseconds / 1000
      : null;

  for (var sourceIndex = 0; sourceIndex < items.length; sourceIndex += 1) {
    final item = items[sourceIndex];
    final value = valueOf(item);
    if (value == null || value.isNaN || value.isInfinite) {
      continue;
    }

    final timestamp = timestampOf(item);
    firstTimestamp ??= timestamp;
    double x;
    if (hasWindow) {
      final windowTimestamp = timestamp;
      if (windowTimestamp == null) {
        continue;
      }
      x = windowTimestamp.difference(windowStart).inMilliseconds / 1000;
    } else if (timestamp != null && firstTimestamp != null) {
      x = timestamp.difference(firstTimestamp).inMilliseconds / 1000;
    } else {
      x = points.length.toDouble();
    }

    if (points.isNotEmpty && x <= points.last.spot.x) {
      x = points.last.spot.x + _repeatedTimestampStepSeconds;
    }

    if (maxGap != null &&
        previousTimestamp != null &&
        timestamp != null &&
        timestamp.difference(previousTimestamp).abs() > maxGap &&
        spots.isNotEmpty &&
        spots.last != FlSpot.nullSpot) {
      spots.add(FlSpot.nullSpot);
    }

    final spot = FlSpot(x, value);
    spots.add(spot);
    pointSpotIndexes.add(spots.length - 1);
    points.add(
      MetricChartPlotPoint(
        spot: spot,
        timestamp: timestamp,
        value: value,
        sourceIndex: sourceIndex,
      ),
    );
    previousTimestamp = timestamp ?? previousTimestamp;
  }

  return MetricChartPlotSeries(
    points,
    spots: spots,
    pointSpotIndexes: pointSpotIndexes,
    minX: hasWindow ? 0 : null,
    maxX: maxX,
  );
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
    MetricChartValueType.bytes => formatBytes(value),
    MetricChartValueType.bytesPerSecond => formatBytesPerSecond(value),
    MetricChartValueType.megabytes => formatMegabytes(value),
  };
}

String formatMetricChartTimestamp(
  DateTime? timestamp, {
  bool includeDate = false,
}) {
  if (timestamp == null) {
    return 'N/A';
  }
  final local = timestamp.toLocal();
  if (includeDate) {
    return DateFormat('MMM d HH:mm').format(local);
  }
  return DateFormat.Hms().format(local);
}

String formatMetricChartTooltip(
  DateTime? timestamp,
  num? value,
  MetricChartValueFormatter formatter, {
  bool includeDate = false,
}) {
  return '${formatMetricChartTimestamp(timestamp, includeDate: includeDate)}\n${formatter(value)}';
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
