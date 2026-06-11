import 'package:flutter_test/flutter_test.dart';
import 'package:homelab_tablet/core/utils/byte_format.dart';
import 'package:homelab_tablet/core/utils/duration_format.dart';
import 'package:homelab_tablet/core/utils/path_safety.dart';
import 'package:homelab_tablet/core/utils/ring_buffer.dart';
import 'package:homelab_tablet/core/utils/temperature_format.dart';
import 'package:homelab_tablet/core/utils/throughput_calculator.dart';

void main() {
  test('formats bytes and temperatures safely', () {
    expect(formatBytes(null), 'N/A');
    expect(formatBytes(1024), '1.00 KB');
    expect(formatTemperature(null), 'N/A');
    expect(formatTemperature(42), '42 C');
    expect(formatTemperature(200), 'N/A');
  });

  test('formats durations', () {
    expect(formatDurationSeconds(null), 'N/A');
    expect(formatDurationSeconds(3661), '1h 1m 1s');
    expect(formatDurationSeconds(90061), '1d 1h 1m 1s');
  });

  test('ring buffer keeps only newest values', () {
    final buffer = RingBuffer<int>(3)
      ..add(1)
      ..add(2)
      ..add(3)
      ..add(4);

    expect(buffer.values, [2, 3, 4]);
  });

  test('throughput handles first sample and counter reset', () {
    final now = DateTime(2026, 1, 1, 12);
    final first = NetworkCounterSample(
      timestamp: now,
      bytesRecv: 100,
      bytesSent: 100,
    );
    expect(
      calculateThroughput(previous: null, current: first).receiveBytesPerSecond,
      0,
    );

    final second = NetworkCounterSample(
      timestamp: now.add(const Duration(seconds: 10)),
      bytesRecv: 1100,
      bytesSent: 600,
    );
    final throughput = calculateThroughput(previous: first, current: second);
    expect(throughput.receiveBytesPerSecond, 100);
    expect(throughput.sendBytesPerSecond, 50);

    final reset = NetworkCounterSample(
      timestamp: now.add(const Duration(seconds: 20)),
      bytesRecv: 10,
      bytesSent: 10,
    );
    expect(
      calculateThroughput(previous: second, current: reset).sendBytesPerSecond,
      0,
    );
  });

  test('virtual path normalization prevents escaping the root', () {
    expect(normalizeVirtualPath('/warm', '/warm/media'), '/warm/media');
    expect(normalizeVirtualPath('/warm', '/warm/../etc'), '/warm');
    expect(normalizeVirtualPath('/warm', '/etc'), '/warm');
  });
}
