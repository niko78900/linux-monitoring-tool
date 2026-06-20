import 'package:flutter/material.dart';

import '../../../../core/config/app_settings.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/section_card.dart';
import 'settings_section_widgets.dart';

class MonitoringSettingsSection extends StatelessWidget {
  const MonitoringSettingsSection({
    super.key,
    required this.settings,
    required this.monitoringUrlController,
    required this.onSave,
    required this.onTest,
  });

  final AppSettings settings;
  final TextEditingController monitoringUrlController;
  final ValueChanged<AppSettings> onSave;
  final VoidCallback onTest;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Monitoring',
      child: Column(
        children: [
          TextField(
            controller: monitoringUrlController,
            decoration: const InputDecoration(
              labelText: 'Monitoring API URL',
              hintText: 'http://100.64.10.22:4040/api',
              helperText:
                  'Real tablet over Tailscale: http://100.64.10.22:4040/api. '
                  'Emulator only: http://10.0.2.2:4040/api.',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          PollingField(
            label: 'Summary polling ms',
            value: settings.summaryPollingMs,
            onChanged: (value) =>
                onSave(settings.copyWith(summaryPollingMs: value)),
          ),
          PollingField(
            label: 'Details polling ms',
            value: settings.detailsPollingMs,
            onChanged: (value) =>
                onSave(settings.copyWith(detailsPollingMs: value)),
          ),
          PollingField(
            label: 'Health polling ms',
            value: settings.healthPollingMs,
            onChanged: (value) =>
                onSave(settings.copyWith(healthPollingMs: value)),
          ),
          PollingField(
            label: 'Docker polling ms',
            value: settings.dockerPollingMs,
            onChanged: (value) =>
                onSave(settings.copyWith(dockerPollingMs: value)),
          ),
          Row(
            children: [
              FilledButton(
                onPressed: () => onSave(
                  settings.copyWith(
                    monitoringApiUrl: monitoringUrlController.text,
                  ),
                ),
                child: const Text('Save monitoring'),
              ),
              const SizedBox(width: AppSpacing.sm),
              OutlinedButton(
                onPressed: onTest,
                child: const Text('Test monitoring API'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
