import 'package:flutter/material.dart';

import '../../../../core/config/app_settings.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/section_card.dart';
import '../../../mobile_alerts/data/mobile_alert_service.dart';
import 'settings_section_widgets.dart';

class PushAlertsSettingsSection extends StatelessWidget {
  const PushAlertsSettingsSection({
    super.key,
    required this.settings,
    required this.tokenController,
    required this.busy,
    required this.notificationPermission,
    required this.readiness,
    required this.registrationLabel,
    required this.channelReadinessLabel,
    required this.statusText,
    required this.onSaveToken,
    required this.onClearToken,
    required this.onEnable,
    required this.onDisable,
    required this.onSave,
    required this.onRefreshStatus,
    required this.onRegister,
    required this.onSendTest,
    required this.onOpenAndroidNotificationSettings,
  });

  final AppSettings settings;
  final TextEditingController tokenController;
  final bool busy;
  final MobileNotificationPermissionState? notificationPermission;
  final MobileAlertReadiness? readiness;
  final String registrationLabel;
  final String channelReadinessLabel;
  final String? statusText;
  final VoidCallback onSaveToken;
  final VoidCallback onClearToken;
  final ValueChanged<AppSettings> onEnable;
  final ValueChanged<AppSettings> onDisable;
  final ValueChanged<AppSettings> onSave;
  final ValueChanged<AppSettings> onRefreshStatus;
  final ValueChanged<AppSettings> onRegister;
  final ValueChanged<AppSettings> onSendTest;
  final VoidCallback onOpenAndroidNotificationSettings;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Push notifications',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: tokenController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Mobile-alert backend token',
              helperText:
                  'Limited token for backend alert registration and tests.',
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              OutlinedButton(
                onPressed: onSaveToken,
                child: const Text('Save alert token'),
              ),
              const SizedBox(width: AppSpacing.sm),
              TextButton(
                onPressed: onClearToken,
                child: const Text('Clear alert token'),
              ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: settings.mobilePushAlertsEnabled,
            onChanged: busy
                ? null
                : (value) => value ? onEnable(settings) : onDisable(settings),
            title: const Text('Enable push alerts'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: settings.mobilePushIncludeRecovery,
            onChanged: (value) =>
                onSave(settings.copyWith(mobilePushIncludeRecovery: value)),
            title: const Text('Include recovery notifications'),
          ),
          SettingsInfoLine(
            label: 'Permission',
            value: notificationPermission?.label ?? 'Not checked',
          ),
          const SizedBox(height: AppSpacing.sm),
          SettingsInfoLine(label: 'Registration', value: registrationLabel),
          const SizedBox(height: AppSpacing.sm),
          SettingsInfoLine(label: 'Channel', value: channelReadinessLabel),
          const SizedBox(height: AppSpacing.sm),
          SettingsInfoLine(
            label: 'Readiness',
            value: readiness?.readinessMessage ?? 'Not checked',
          ),
          if (statusText != null) ...[
            const SizedBox(height: AppSpacing.sm),
            SettingsInfoLine(label: 'Last action', value: statusText!),
          ],
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              OutlinedButton.icon(
                onPressed: busy ? null : () => onRefreshStatus(settings),
                icon: const Icon(Icons.sync),
                label: const Text('Refresh push status'),
              ),
              OutlinedButton.icon(
                onPressed: busy ? null : () => onRegister(settings),
                icon: const Icon(Icons.app_registration),
                label: const Text('Re-register this tablet'),
              ),
              FilledButton.icon(
                onPressed: busy ? null : () => onSendTest(settings),
                icon: const Icon(Icons.notifications_active),
                label: const Text('Send test notification'),
              ),
              OutlinedButton.icon(
                onPressed: onOpenAndroidNotificationSettings,
                icon: const Icon(Icons.settings),
                label: const Text('Android notification settings'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
