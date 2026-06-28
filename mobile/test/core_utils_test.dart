import 'package:flutter_test/flutter_test.dart';
import 'package:homelab_tablet/core/config/app_settings.dart';
import 'package:homelab_tablet/core/utils/byte_format.dart';
import 'package:homelab_tablet/core/utils/display_name_format.dart';
import 'package:homelab_tablet/core/utils/duration_format.dart';
import 'package:homelab_tablet/core/utils/hardware_display_format.dart';
import 'package:homelab_tablet/core/utils/path_safety.dart';
import 'package:homelab_tablet/core/utils/ring_buffer.dart';
import 'package:homelab_tablet/core/utils/temperature_format.dart';
import 'package:homelab_tablet/core/utils/threshold_tone.dart';
import 'package:homelab_tablet/core/utils/throughput_calculator.dart';
import 'package:homelab_tablet/core/widgets/status_tone.dart';
import 'package:homelab_tablet/features/files/data/file_browser_utils.dart';

void main() {
  test('formats bytes and temperatures safely', () {
    expect(formatBytes(null), 'N/A');
    expect(formatBytes(1024), '1.00 KB');
    expect(formatBytesPerSecond(0), '0 B/s');
    expect(formatBytesPerSecond(512), '512 B/s');
    expect(formatBytesPerSecond(16 * 1024), '16 KB/s');
    expect(formatBytesPerSecond(1.25 * 1024 * 1024), '1.3 MB/s');
    expect(formatTemperature(null), 'N/A');
    expect(formatTemperature(42), '42 C');
    expect(formatTemperature(200), 'N/A');
  });

  test('formats durations', () {
    expect(formatDurationSeconds(null), 'N/A');
    expect(formatDurationSeconds(3661), '1h 1m 1s');
    expect(formatDurationSeconds(90061), '1d 1h 1m 1s');
  });

  test('formats host and device display names without mutating raw values', () {
    expect(formatHostDisplayName('server'), 'Server');
    expect(formatHostDisplayName('homelab-server'), 'Homelab Server');
    expect(formatDeviceDisplayName('main-pc'), 'Main PC');
    expect(formatDeviceDisplayName('tablet_peer'), 'Tablet Peer');
    expect(
      formatHostDisplayName('server.tailnet.ts.net'),
      'server.tailnet.ts.net',
    );
    expect(formatDeviceDisplayName(null), 'Unknown');
    expect(formatHostDisplayName(''), 'Unknown');
  });

  test('formats noisy hardware values for display', () {
    expect(
      formatOperatingSystemDisplayName(
        'Linux-6.12.90+deb13.1-amd64-x86_64-with-glibc2.41',
      ),
      'Debian 13',
    );
    expect(formatKernelDisplayName('6.12.90+deb13.1-amd64'), 'Linux 6.12');
    expect(
      formatCpuModelDisplayName('13th Gen Intel(R) Core(TM) i5-13400F'),
      'Intel Core i5-13400F',
    );
    expect(formatOperatingSystemDisplayName('CustomOS'), 'CustomOS');
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

  test(
    'soft delete target stays inside trash and preview rules are bounded',
    () {
      final target = buildSoftDeletePath(
        virtualRoot: '/warm',
        sourcePath: '/warm/videos/movie.mkv',
        now: DateTime.utc(2026, 6, 11, 20, 15, 30),
      );

      expect(target.startsWith('/warm/.tablet-trash/'), isTrue);
      expect(isImagePreviewable('photo.jpg'), isTrue);
      expect(isTextPreviewable('server.log'), isTrue);
      expect(isTextPreviewable('script.py'), isTrue);
      expect(isTextPreviewable('query.sql'), isTrue);
      expect(isExternalPreviewable('runbook.pdf'), isTrue);
      expect(isExternalPreviewable('slides.pptx'), isTrue);
      expect(isVideoPreviewable('movie.mkv'), isTrue);
      expect(isImagePreviewable('archive.zip'), isFalse);
    },
  );

  test('sftp mutation flags default to disabled', () {
    final settings = AppSettings.defaults();

    expect(settings.allowSftpUpload, isFalse);
    expect(settings.allowSftpCreateDirectory, isFalse);
    expect(settings.allowSftpRename, isFalse);
    expect(settings.allowSftpMove, isFalse);
    expect(settings.allowSftpSoftDelete, isFalse);
    expect(settings.sftpBackgroundTimeout, SftpBackgroundTimeout.fiveMinutes);
    expect(canMutateFiles(settings), isFalse);
  });

  test('threshold tone follows homelab 60/80 boundaries', () {
    expect(thresholdTone(null), StatusTone.neutral);
    expect(thresholdTone(60), StatusTone.healthy);
    expect(thresholdTone(61), StatusTone.warning);
    expect(thresholdTone(80), StatusTone.warning);
    expect(thresholdTone(81), StatusTone.critical);
  });

  test('temperature tone follows homelab thermal boundaries', () {
    expect(temperatureTone(null), StatusTone.neutral);
    expect(temperatureTone(69), StatusTone.healthy);
    expect(temperatureTone(70), StatusTone.warning);
    expect(temperatureTone(84), StatusTone.warning);
    expect(temperatureTone(85), StatusTone.critical);
  });
}
