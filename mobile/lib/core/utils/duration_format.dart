String formatDurationSeconds(num? value) {
  if (value == null || value.isNaN) {
    return 'N/A';
  }
  final total = value.floor().clamp(0, 1 << 62);
  final days = total ~/ 86400;
  final hours = (total % 86400) ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final seconds = total % 60;
  final parts = <String>[];
  if (days > 0) {
    parts.add('${days}d');
  }
  parts.add('${hours}h');
  parts.add('${minutes}m');
  parts.add('${seconds}s');
  return parts.join(' ');
}

String formatPollingInterval(int ms) {
  if (ms >= 60 * 60 * 1000) {
    return '1 hour';
  }
  if (ms >= 60 * 1000) {
    final minutes = ms / (60 * 1000);
    return '${_trim(minutes, minutes >= 10 ? 0 : 1)} min';
  }
  if (ms >= 1000) {
    final seconds = ms / 1000;
    return '${_trim(seconds, seconds >= 10 ? 0 : 1)} sec';
  }
  return '$ms ms';
}

String _trim(num value, int decimals) {
  return value
      .toStringAsFixed(decimals)
      .replaceFirst(RegExp(r'\.0+$'), '')
      .replaceFirst(RegExp(r'(\.\d*[1-9])0+$'), r'$1');
}
