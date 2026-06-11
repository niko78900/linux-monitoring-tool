String formatTemperature(num? value) {
  if (value == null || value.isNaN || value < -20 || value > 130) {
    return 'N/A';
  }
  return '${value.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '')} C';
}
