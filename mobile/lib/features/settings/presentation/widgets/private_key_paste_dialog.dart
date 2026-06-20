import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';

Future<String?> showPrivateKeyPasteDialog(
  BuildContext context, {
  required String title,
  required String label,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _PrivateKeyPasteDialog(title: title, label: label),
  );
}

class _PrivateKeyPasteDialog extends StatefulWidget {
  const _PrivateKeyPasteDialog({required this.title, required this.label});

  final String title;
  final String label;

  @override
  State<_PrivateKeyPasteDialog> createState() => _PrivateKeyPasteDialogState();
}

class _PrivateKeyPasteDialogState extends State<_PrivateKeyPasteDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
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
        child: SizedBox(
          width: 560,
          child: TextField(
            controller: _controller,
            autofocus: true,
            minLines: 10,
            maxLines: 14,
            keyboardType: TextInputType.multiline,
            decoration: InputDecoration(
              alignLabelWithHint: true,
              labelText: widget.label,
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Save key'),
        ),
      ],
      actionsPadding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.md,
      ),
    );
  }
}
