import '../widgets/status_tone.dart';

StatusTone thresholdTone(num? value) {
  if (value == null || value.isNaN) {
    return StatusTone.neutral;
  }
  if (value >= 81) {
    return StatusTone.critical;
  }
  if (value >= 61) {
    return StatusTone.warning;
  }
  return StatusTone.healthy;
}
