import 'package:flutter/material.dart';

import '../../../../core/config/app_settings.dart';
import '../../../../core/widgets/section_card.dart';

class DebugSettingsSection extends StatelessWidget {
  const DebugSettingsSection({
    super.key,
    required this.settings,
    required this.onSave,
    required this.onResetOnboarding,
  });

  final AppSettings settings;
  final ValueChanged<AppSettings> onSave;
  final VoidCallback onResetOnboarding;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Debug',
      child: Column(
        children: [
          SwitchListTile(
            value: settings.showRawApiErrors,
            onChanged: (value) =>
                onSave(settings.copyWith(showRawApiErrors: value)),
            title: const Text('Show raw API errors'),
          ),
          SwitchListTile(
            value: settings.showRequestTiming,
            onChanged: (value) =>
                onSave(settings.copyWith(showRequestTiming: value)),
            title: const Text('Show request timing'),
          ),
          TextButton(
            onPressed: onResetOnboarding,
            child: const Text('Run onboarding again'),
          ),
        ],
      ),
    );
  }
}
