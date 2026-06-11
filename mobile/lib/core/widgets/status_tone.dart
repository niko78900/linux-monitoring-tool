import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

enum StatusTone { healthy, warning, critical, unknown, offline, neutral }

Color toneColor(StatusTone tone) {
  return switch (tone) {
    StatusTone.healthy => AppColors.healthy,
    StatusTone.warning => AppColors.warning,
    StatusTone.critical => AppColors.critical,
    StatusTone.offline => AppColors.critical,
    StatusTone.unknown => AppColors.neutral,
    StatusTone.neutral => AppColors.neutral,
  };
}
