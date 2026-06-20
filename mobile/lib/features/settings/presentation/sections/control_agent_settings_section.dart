import 'package:flutter/material.dart';

import '../../../../core/config/app_settings.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/section_card.dart';

class ControlAgentSettingsSection extends StatelessWidget {
  const ControlAgentSettingsSection({
    super.key,
    required this.settings,
    required this.controlUrlController,
    required this.controlTokenController,
    required this.onSave,
    required this.onTest,
    required this.onClearToken,
  });

  final AppSettings settings;
  final TextEditingController controlUrlController;
  final TextEditingController controlTokenController;
  final Future<void> Function(AppSettings settings) onSave;
  final VoidCallback onTest;
  final VoidCallback onClearToken;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Control Agent',
      child: Column(
        children: [
          TextField(
            controller: controlUrlController,
            decoration: const InputDecoration(
              labelText: 'Control API URL',
              hintText: 'http://100.64.10.22:4042/api',
              helperText:
                  'Control agent endpoint for a real tablet over Tailscale. '
                  'Use /api on port 4042.',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: controlTokenController,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Control API token'),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              FilledButton(
                onPressed: () => onSave(settings),
                child: const Text('Save control'),
              ),
              const SizedBox(width: AppSpacing.sm),
              OutlinedButton(
                onPressed: onTest,
                child: const Text('Test control API'),
              ),
              const SizedBox(width: AppSpacing.sm),
              TextButton(
                onPressed: onClearToken,
                child: const Text('Clear token'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
