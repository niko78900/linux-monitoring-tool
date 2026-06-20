import 'package:flutter/material.dart';

import '../../../../core/config/app_settings.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/section_card.dart';
import 'settings_section_widgets.dart';

class FilesSettingsSection extends StatelessWidget {
  const FilesSettingsSection({
    super.key,
    required this.settings,
    required this.nameController,
    required this.hostController,
    required this.portController,
    required this.userController,
    required this.rootController,
    required this.keySummary,
    required this.trustedFingerprint,
    required this.passphraseRemembered,
    required this.testing,
    required this.onSaveProfiles,
    required this.onSave,
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
  final TextEditingController rootController;
  final String? keySummary;
  final String? trustedFingerprint;
  final bool passphraseRemembered;
  final bool testing;
  final ValueChanged<AppSettings> onSaveProfiles;
  final ValueChanged<AppSettings> onSave;
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
      title: 'Files',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Used by the Files page for restricted SFTP browsing and transfers. Keep this separate from the Terminal SSH shell profile.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: nameController,
            decoration: const InputDecoration(labelText: 'SFTP profile name'),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: hostController,
            decoration: const InputDecoration(labelText: 'SFTP host'),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: portController,
            decoration: const InputDecoration(labelText: 'SFTP port'),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: userController,
            decoration: const InputDecoration(labelText: 'SFTP username'),
          ),
          const SizedBox(height: AppSpacing.md),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: settings.sftpProfile.storePassphrase,
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
          TextField(
            controller: rootController,
            decoration: const InputDecoration(
              labelText: 'Configured virtual root',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          DropdownButtonFormField<SftpBackgroundTimeout>(
            initialValue: settings.sftpBackgroundTimeout,
            decoration: const InputDecoration(
              labelText: 'SFTP background timeout',
            ),
            items: [
              for (final timeout in SftpBackgroundTimeout.values)
                DropdownMenuItem(value: timeout, child: Text(timeout.label)),
            ],
            onChanged: (value) {
              if (value != null) {
                onSave(settings.copyWith(sftpBackgroundTimeout: value));
              }
            },
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
                child: const Text('Save files'),
              ),
              OutlinedButton.icon(
                onPressed: () => onImportKey(settings),
                icon: const Icon(Icons.upload_file),
                label: Text(
                  settings.sftpProfile.hasImportedKey
                      ? 'Replace key'
                      : 'Import restricted key',
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => onPasteKey(settings),
                icon: const Icon(Icons.content_paste),
                label: const Text('Paste restricted key'),
              ),
              TextButton(
                onPressed: settings.sftpProfile.hasImportedKey
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
                child: Text(testing ? 'Testing...' : 'Test SFTP connection'),
              ),
              TextButton(
                onPressed: trustedFingerprint == null
                    ? null
                    : () => onResetTrustedFingerprint(settings.sftpProfile),
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
