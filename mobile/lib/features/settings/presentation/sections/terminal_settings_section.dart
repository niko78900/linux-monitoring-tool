import 'package:flutter/material.dart';

import '../../../../core/config/app_settings.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/section_card.dart';
import 'settings_section_widgets.dart';

class TerminalSettingsSection extends StatelessWidget {
  const TerminalSettingsSection({
    super.key,
    required this.settings,
    required this.nameController,
    required this.hostController,
    required this.portController,
    required this.userController,
    required this.keySummary,
    required this.trustedFingerprint,
    required this.passphraseRemembered,
    required this.testing,
    required this.onSaveProfiles,
    required this.onSetPassphraseStorage,
    required this.onForgetPassphrase,
    required this.onImportKey,
    required this.onPasteKey,
    required this.onRemoveKey,
    required this.onTest,
    required this.onResetTrustedFingerprint,
  });

  final AppSettings settings;
  final TextEditingController nameController;
  final TextEditingController hostController;
  final TextEditingController portController;
  final TextEditingController userController;
  final String? keySummary;
  final String? trustedFingerprint;
  final bool passphraseRemembered;
  final bool testing;
  final ValueChanged<AppSettings> onSaveProfiles;
  final void Function(AppSettings settings, bool value) onSetPassphraseStorage;
  final ValueChanged<AppSettings> onForgetPassphrase;
  final ValueChanged<AppSettings> onImportKey;
  final ValueChanged<AppSettings> onPasteKey;
  final ValueChanged<AppSettings> onRemoveKey;
  final ValueChanged<AppSettings> onTest;
  final ValueChanged<ConnectionProfile> onResetTrustedFingerprint;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Terminal',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Used by the Terminal page for interactive SSH shell access. Files/SFTP has its own restricted profile below.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: nameController,
            decoration: const InputDecoration(labelText: 'SSH profile name'),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: hostController,
            decoration: const InputDecoration(labelText: 'SSH host'),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: portController,
            decoration: const InputDecoration(labelText: 'SSH port'),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: userController,
            decoration: const InputDecoration(labelText: 'SSH username'),
          ),
          const SizedBox(height: AppSpacing.md),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: settings.sshProfile.storePassphrase,
            onChanged: (value) => onSetPassphraseStorage(settings, value),
            title: const Text('Remember passphrase after it is entered'),
            subtitle: Text(
              passphraseRemembered
                  ? 'A passphrase is saved in Android secure storage.'
                  : 'You will be asked during connect or test, then can choose whether to remember it.',
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: passphraseRemembered
                  ? () => onForgetPassphrase(settings)
                  : null,
              icon: const Icon(Icons.lock_reset),
              label: const Text('Forget remembered passphrase'),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SettingsInfoLine(
            label: 'Imported key',
            value: keySummary ?? 'No key imported',
          ),
          const SizedBox(height: AppSpacing.sm),
          SettingsInfoLine(
            label: 'Trusted host fingerprint',
            value: trustedFingerprint ?? 'No trusted fingerprint stored',
            selectable: true,
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              FilledButton(
                onPressed: () => onSaveProfiles(settings),
                child: const Text('Save terminal'),
              ),
              OutlinedButton.icon(
                onPressed: () => onImportKey(settings),
                icon: const Icon(Icons.upload_file),
                label: Text(
                  settings.sshProfile.hasImportedKey
                      ? 'Replace key'
                      : 'Import private key',
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => onPasteKey(settings),
                icon: const Icon(Icons.content_paste),
                label: const Text('Paste private key'),
              ),
              TextButton(
                onPressed: settings.sshProfile.hasImportedKey
                    ? () => onRemoveKey(settings)
                    : null,
                child: const Text('Remove key'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              OutlinedButton(
                onPressed: testing ? null : () => onTest(settings),
                child: Text(testing ? 'Testing...' : 'Test SSH connection'),
              ),
              TextButton(
                onPressed: trustedFingerprint == null
                    ? null
                    : () => onResetTrustedFingerprint(settings.sshProfile),
                child: const Text('Reset trusted fingerprint'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
