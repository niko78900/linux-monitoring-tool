import 'package:flutter/material.dart';

import '../../../../core/config/app_settings.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/section_card.dart';

class TabletSettingsSection extends StatelessWidget {
  const TabletSettingsSection({
    super.key,
    required this.settings,
    required this.onSave,
    required this.onManualLock,
  });

  final AppSettings settings;
  final ValueChanged<AppSettings> onSave;
  final VoidCallback onManualLock;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Tablet',
      child: Column(
        children: [
          SwitchListTile(
            value: settings.keepScreenAwakeOnOverview,
            onChanged: (value) =>
                onSave(settings.copyWith(keepScreenAwakeOnOverview: value)),
            title: const Text('Keep screen awake on Overview'),
          ),
          SwitchListTile(
            value: settings.requirePrivilegedUnlock,
            onChanged: (value) =>
                onSave(settings.copyWith(requirePrivilegedUnlock: value)),
            title: const Text('Privileged-tab lock'),
          ),
          DropdownButtonFormField<PrivilegedUnlockTimeout>(
            initialValue: settings.unlockTimeout,
            decoration: const InputDecoration(labelText: 'Unlock timeout'),
            items: [
              for (final option in PrivilegedUnlockTimeout.values)
                DropdownMenuItem(value: option, child: Text(option.label)),
            ],
            onChanged: (value) {
              if (value != null) {
                onSave(settings.copyWith(unlockTimeout: value));
              }
            },
          ),
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: onManualLock,
              icon: const Icon(Icons.lock),
              label: const Text('Manually lock now'),
            ),
          ),
        ],
      ),
    );
  }
}
