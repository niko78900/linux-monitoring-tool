import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/models/file_browser_models.dart';
import '../../domain/models/remote_file_entry.dart';

Future<void> showImagePreviewDialog(
  BuildContext context, {
  required String localPath,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) =>
        Dialog(child: InteractiveViewer(child: Image.file(File(localPath)))),
  );
}

Future<void> showTextPreviewDialog(
  BuildContext context, {
  required String title,
  required String text,
  required VoidCallback onCopied,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 720,
        child: SingleChildScrollView(
          child: SelectableText(
            text,
            style: const TextStyle(fontFamily: 'monospace'),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: text));
            Navigator.of(context).pop();
            onCopied();
          },
          child: const Text('Copy'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

Future<void> showUnsupportedPreviewDialog(
  BuildContext context, {
  required RemoteFileEntry entry,
  required VoidCallback onCopyPath,
  required VoidCallback onDownload,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(entry.name),
      content: const Text(
        'Preview is unavailable for this file type. You can still download it or copy the remote path.',
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
            onCopyPath();
          },
          child: const Text('Copy path'),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
            onDownload();
          },
          child: const Text('Download'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

Future<String?> showRemoteSearchPrompt(
  BuildContext context, {
  required String initialQuery,
}) async {
  final controller = TextEditingController(text: initialQuery);
  try {
    return await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remote search'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Search name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Search'),
          ),
        ],
      ),
    );
  } finally {
    controller.dispose();
  }
}

Future<void> showRemoteSearchResultsDialog(
  BuildContext context, {
  required List<RemoteSearchResult> results,
  required ValueChanged<String> onOpenDirectory,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Search results'),
      content: SizedBox(
        width: 720,
        child: results.isEmpty
            ? const Text('No results found.')
            : ListView.builder(
                shrinkWrap: true,
                itemCount: results.length,
                itemBuilder: (context, index) {
                  final result = results[index];
                  return ListTile(
                    leading: Icon(
                      result.isDirectory
                          ? Icons.folder
                          : Icons.insert_drive_file,
                    ),
                    title: Text(result.name),
                    subtitle: Text(result.entryPath),
                    onTap: () {
                      Navigator.of(context).pop();
                      if (result.isDirectory) {
                        onOpenDirectory(result.entryPath);
                      }
                    },
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

Future<String?> showTextInputDialog(
  BuildContext context, {
  required String title,
  String initialValue = '',
  String confirmLabel = 'Save',
  String? labelText,
}) async {
  final controller = TextEditingController(text: initialValue);
  try {
    return await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: labelText == null
              ? null
              : InputDecoration(labelText: labelText),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  } finally {
    controller.dispose();
  }
}
