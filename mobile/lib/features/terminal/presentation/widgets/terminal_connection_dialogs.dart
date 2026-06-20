import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../domain/models/ssh_connection_models.dart';

Future<bool> showHostTrustDialog(
  BuildContext context,
  SshHostFingerprint hostKey,
) async {
  final trusted = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Trust this host key?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Verify the server fingerprint before trusting this connection.',
            ),
            const SizedBox(height: AppSpacing.md),
            SelectableText(hostKey.displayValue),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Reject'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Trust'),
          ),
        ],
      );
    },
  );
  return trusted ?? false;
}

Future<PassphrasePromptResult?> showPassphrasePromptDialog(
  BuildContext context, {
  required String title,
  bool rememberInitially = false,
}) {
  return showDialog<PassphrasePromptResult>(
    context: context,
    builder: (context) => _PassphrasePromptDialog(
      title: title,
      rememberInitially: rememberInitially,
    ),
  );
}

class _PassphrasePromptDialog extends StatefulWidget {
  const _PassphrasePromptDialog({
    required this.title,
    required this.rememberInitially,
  });

  final String title;
  final bool rememberInitially;

  @override
  State<_PassphrasePromptDialog> createState() =>
      _PassphrasePromptDialogState();
}

class _PassphrasePromptDialogState extends State<_PassphrasePromptDialog> {
  late final TextEditingController _controller;
  late bool _remember;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _remember = widget.rememberInitially;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _controller,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Passphrase'),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: AppSpacing.sm),
            CheckboxListTile(
              value: _remember,
              onChanged: (value) => setState(() => _remember = value ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Remember in secure storage'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Continue')),
      ],
    );
  }

  void _submit() {
    final passphrase = _controller.text.trim();
    if (passphrase.isEmpty) {
      return;
    }
    Navigator.of(
      context,
    ).pop(PassphrasePromptResult(passphrase: passphrase, remember: _remember));
  }
}
