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
    required this.passphraseController,
    required this.keySummary,
    required this.trustedFingerprint,
    required this.testing,
    required this.onSaveProfiles,
    required this.onSetPassphraseStorage,
    required this.onImportKey,
    required this.onPasteKey,
    required this.onRemoveKey,
    required this.onTest,
    required this.onResetTrustedFingerprint,
    required this.onSave,
  });

  final AppSettings settings;
  final TextEditingController nameController;
  final TextEditingController hostController;
  final TextEditingController portController;
  final TextEditingController userController;
  final TextEditingController passphraseController;
  final String? keySummary;
  final String? trustedFingerprint;
  final bool testing;
  final ValueChanged<AppSettings> onSaveProfiles;
  final void Function(AppSettings settings, bool value) onSetPassphraseStorage;
  final ValueChanged<AppSettings> onImportKey;
  final ValueChanged<AppSettings> onPasteKey;
  final ValueChanged<AppSettings> onRemoveKey;
  final ValueChanged<AppSettings> onTest;
  final ValueChanged<ConnectionProfile> onResetTrustedFingerprint;
  final ValueChanged<AppSettings> onSave;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Terminal',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
            title: const Text('Store passphrase in secure storage'),
          ),
          if (settings.sshProfile.storePassphrase) ...[
            TextField(
              controller: passphraseController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'SSH key passphrase',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
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
          const SizedBox(height: AppSpacing.lg),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: settings.allowSftpUpload,
            onChanged: (value) =>
                onSave(settings.copyWith(allowSftpUpload: value)),
            title: const Text('Allow uploads'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: settings.allowSftpCreateDirectory,
            onChanged: (value) =>
                onSave(settings.copyWith(allowSftpCreateDirectory: value)),
            title: const Text('Allow create directory'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: settings.allowSftpRename,
            onChanged: (value) =>
                onSave(settings.copyWith(allowSftpRename: value)),
            title: const Text('Allow rename'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: settings.allowSftpMove,
            onChanged: (value) =>
                onSave(settings.copyWith(allowSftpMove: value)),
            title: const Text('Allow move'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: settings.allowSftpSoftDelete,
            onChanged: (value) =>
                onSave(settings.copyWith(allowSftpSoftDelete: value)),
            title: const Text('Allow soft delete'),
          ),
        ],
      ),
    );
  }
}
