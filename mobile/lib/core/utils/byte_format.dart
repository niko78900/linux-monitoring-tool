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
