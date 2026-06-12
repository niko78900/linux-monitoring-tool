const _byteUnits = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];

String formatBytes(num? value) {
  if (value == null || value.isNaN) {
    return 'N/A';
  }
  final sign = value < 0 ? '-' : '';
  var normalized = value.abs().toDouble();
  var unit = 0;
  while (normalized >= 1024 && unit < _byteUnits.length - 1) {
    normalized /= 1024;
    unit += 1;
  }
  if (unit == 0) {
    return '$sign${normalized.toStringAsFixed(0)} ${_byteUnits[unit]}';
  }
  final decimals = normalized >= 10 ? 1 : 2;
  return '$sign${normalized.toStringAsFixed(decimals)} ${_byteUnits[unit]}';
}

String formatMegabytes(num? value) {
  if (value == null || value.isNaN) {
    return 'N/A';
  }
  return formatBytes(value * 1024 * 1024);
}

String formatBytesPerSecond(num? value) {
  if (value == null || value.isNaN) {
    return 'N/A';
  }
  return '${_formatBytesCompact(value)}/s';
}

String _formatBytesCompact(num value) {
  final sign = value < 0 ? '-' : '';
  var normalized = value.abs().toDouble();
  var unit = 0;
  while (normalized >= 1024 && unit < _byteUnits.length - 1) {
    normalized /= 1024;
    unit += 1;
  }
  if (unit == 0) {
    return '$sign${normalized.toStringAsFixed(0)} ${_byteUnits[unit]}';
  }
  final hasFraction = (normalized - normalized.round()).abs() > 0.05;
  final decimals = normalized >= 10 && !hasFraction ? 0 : 1;
  return '$sign${normalized.toStringAsFixed(decimals)} ${_byteUnits[unit]}';
}
