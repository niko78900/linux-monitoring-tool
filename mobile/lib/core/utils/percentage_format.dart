String formatPercent(num? value, {int decimals = 0}) {
  if (value == null || value.isNaN) {
    return 'N/A';
  }
  return '${value.toStringAsFixed(decimals)}%';
}

double clampPercent(num? value) {
  if (value == null || value.isNaN) {
    return 0;
  }
  return value.toDouble().clamp(0, 100);
}
