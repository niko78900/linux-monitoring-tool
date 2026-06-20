import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/byte_format.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../domain/models/remote_file_entry.dart';

enum FileEntryAction { preview, download, rename, move, softDelete }

class RemoteFileList extends StatelessWidget {
  const RemoteFileList({
    super.key,
    required this.entries,
    required this.currentPath,
    required this.dateFormat,
    required this.onOpenDirectory,
    required this.onPreview,
    required this.onDownload,
    required this.onEntryAction,
    required this.onCopyPath,
  });

  final List<RemoteFileEntry> entries;
  final String currentPath;
  final DateFormat dateFormat;
  final ValueChanged<RemoteFileEntry> onOpenDirectory;
  final ValueChanged<RemoteFileEntry> onPreview;
  final ValueChanged<RemoteFileEntry> onDownload;
  final void Function(RemoteFileEntry entry, FileEntryAction action)
  onEntryAction;
  final ValueChanged<String> onCopyPath;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return EmptyState(
        icon: Icons.folder_open,
        title: 'No files in this directory',
        message: 'Current path: $currentPath',
      );
    }

    return ListView.separated(
      itemCount: entries.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final entry = entries[index];
        final subtitle = <String>[
          if (entry.isSymbolicLink) 'symlink',
          if (!entry.isDirectory && entry.sizeBytes != null)
            formatBytes(entry.sizeBytes!),
          if (entry.modifiedAt != null) dateFormat.format(entry.modifiedAt!),
        ].join('  |  ');

        return ListTile(
          leading: Icon(
            entry.isSymbolicLink
                ? Icons.link_off
                : entry.isDirectory
                ? Icons.folder
                : Icons.insert_drive_file,
          ),
          title: Text(entry.name),
          subtitle: subtitle.isEmpty ? null : Text(subtitle),
          onTap: entry.isDirectory && !entry.isSymbolicLink
              ? () => onOpenDirectory(entry)
              : (!entry.isSymbolicLink ? () => onPreview(entry) : null),
          trailing: Wrap(
            spacing: AppSpacing.xs,
            children: [
              IconButton(
                tooltip: 'Copy remote path',
                onPressed: () => onCopyPath(entry.path),
                icon: const Icon(Icons.copy_all),
              ),
              if (!entry.isSymbolicLink)
                IconButton(
                  tooltip: 'Preview',
                  onPressed: entry.isDirectory
                      ? null
                      : () => onEntryAction(entry, FileEntryAction.preview),
                  icon: const Icon(Icons.visibility),
                ),
              if (!entry.isDirectory && !entry.isSymbolicLink)
                IconButton(
                  tooltip: 'Download file',
                  onPressed: () => onDownload(entry),
                  icon: const Icon(Icons.download),
                ),
              PopupMenuButton<FileEntryAction>(
                onSelected: (action) => onEntryAction(entry, action),
                itemBuilder: (context) => [
                  if (!entry.isDirectory && !entry.isSymbolicLink)
                    const PopupMenuItem(
                      value: FileEntryAction.preview,
                      child: Text('Preview'),
                    ),
                  const PopupMenuItem(
                    value: FileEntryAction.rename,
                    child: Text('Rename'),
                  ),
                  const PopupMenuItem(
                    value: FileEntryAction.move,
                    child: Text('Move'),
                  ),
                  const PopupMenuItem(
                    value: FileEntryAction.softDelete,
                    child: Text('Soft delete'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
