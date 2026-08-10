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
    this.wakeOnly = false,
  });

  final AppSettings settings;
  final TextEditingController controlUrlController;
  final TextEditingController controlTokenController;
  final Future<void> Function(AppSettings settings) onSave;
  final VoidCallback onTest;
  final VoidCallback onClearToken;
  final bool wakeOnly;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: wakeOnly ? 'Wake-on-LAN' : 'Control Agent',
      child: Column(
        children: [
          TextField(
            controller: controlUrlController,
            decoration: InputDecoration(
              labelText: wakeOnly ? 'Wake API URL' : 'Control API URL',
              hintText: 'http://100.64.10.22:4042/api',
              helperText: wakeOnly
                  ? 'Control agent endpoint used only for health checks and '
                        'waking the main PC.'
                  : 'Control agent endpoint for a real tablet over Tailscale. '
                        'Use /api on port 4042.',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: controlTokenController,
            obscureText: true,
            decoration: InputDecoration(
              labelText: wakeOnly ? 'Wake-only API token' : 'Control API token',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              FilledButton(
                onPressed: () => onSave(settings),
                child: Text(wakeOnly ? 'Save wake access' : 'Save control'),
              ),
              const SizedBox(width: AppSpacing.sm),
              OutlinedButton(
                onPressed: onTest,
                child: Text(wakeOnly ? 'Test wake API' : 'Test control API'),
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
