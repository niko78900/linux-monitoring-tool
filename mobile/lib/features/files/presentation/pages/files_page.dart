import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';

import '../../../../core/config/app_settings.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/byte_format.dart';
import '../../../../core/utils/path_safety.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../../core/widgets/status_tone.dart';
import '../../data/file_download_service.dart';
import '../../data/sftp_connection_service.dart';
import '../../domain/models/remote_file_entry.dart';
import '../../domain/models/transfer_item.dart';
import '../../presentation/widgets/transfer_queue_panel.dart';
import '../../../terminal/presentation/widgets/terminal_connection_dialogs.dart';

class FilesPage extends ConsumerStatefulWidget {
  const FilesPage({super.key});

  @override
  ConsumerState<FilesPage> createState() => _FilesPageState();
}

class _FilesPageState extends ConsumerState<FilesPage>
    with WidgetsBindingObserver {
  final _searchController = TextEditingController();
  final _dateFormat = DateFormat.yMd().add_Hm();

  SftpSessionConnection? _connection;
  _FilesStatus _status = _FilesStatus.disconnected;
  String? _message;
  String? _currentPath;
  List<RemoteFileEntry> _entries = const [];
  List<TransferItem> _transfers = const [];
  final Map<String, DownloadCancellationToken> _tokens =
      <String, DownloadCancellationToken>{};
  String? _activeTransferId;
  _FilesSort _sort = _FilesSort.name;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    _cancelOutstandingTransfers(mutateState: false);
    final connection = _connection;
    _connection = null;
    if (connection != null) {
      unawaited(connection.close());
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(
        _disconnect(message: 'SFTP session closed after the app moved to background.'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsControllerProvider);
    final profile = settings.sftpProfile;
    final root = normalizeVirtualPath(settings.sftpVirtualRoot, settings.sftpVirtualRoot);

    if (!profile.isConfigured) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: EmptyState(
          icon: Icons.folder,
          title: 'Configure the SFTP profile first',
          message:
              'Set the restricted SFTP host, port, username, and virtual root in Settings before opening Files.',
          action: FilledButton(
            onPressed: () => context.go('/settings'),
            child: const Text('Open Settings'),
          ),
        ),
      );
    }
    if (!profile.hasImportedKey) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: EmptyState(
          icon: Icons.key,
          title: 'Import the restricted SFTP key',
          message:
              'Files uses a separate restricted key and account. Import that key in Settings before connecting.',
          action: FilledButton(
            onPressed: () => context.go('/settings'),
            child: const Text('Open Settings'),
          ),
        ),
      );
    }

    final visibleEntries = _sortedEntries(
      _filteredEntries(_entries, _searchController.text),
    );

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              StatusBadge(label: _status.label, tone: _status.tone),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Text(_currentPath ?? root),
              ),
              if (_message != null)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Text(_message!),
                ),
              FilledButton.icon(
                onPressed: _status == _FilesStatus.connecting
                    ? null
                    : () => _connect(settings),
                icon: const Icon(Icons.folder_open),
                label: Text(
                  _status == _FilesStatus.connected ? 'Reconnect' : 'Connect',
                ),
              ),
              OutlinedButton.icon(
                onPressed: _connection == null ? null : _disconnect,
                icon: const Icon(Icons.link_off),
                label: const Text('Disconnect'),
              ),
              OutlinedButton.icon(
                onPressed: _connection == null ? null : () => _loadDirectory(root),
                icon: const Icon(Icons.home),
                label: const Text('Root'),
              ),
              OutlinedButton.icon(
                onPressed: _connection == null ? null : _goBack,
                icon: const Icon(Icons.arrow_upward),
                label: const Text('Back'),
              ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: _connection == null
                    ? null
                    : () => _loadDirectory(_currentPath ?? root),
                icon: const Icon(Icons.refresh),
              ),
              IconButton(
                tooltip: 'Copy remote path',
                onPressed: () => _copyPath(_currentPath ?? root),
                icon: const Icon(Icons.copy_all),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 280,
                child: TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Search current directory',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<_FilesSort>(
                  initialValue: _sort,
                  decoration: const InputDecoration(labelText: 'Sort'),
                  items: const [
                    DropdownMenuItem(
                      value: _FilesSort.name,
                      child: Text('Name'),
                    ),
                    DropdownMenuItem(
                      value: _FilesSort.modified,
                      child: Text('Modified'),
                    ),
                    DropdownMenuItem(
                      value: _FilesSort.size,
                      child: Text('Size'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _sort = value);
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final list = _RemoteFileList(
                  entries: visibleEntries,
                  currentPath: _currentPath ?? root,
                  dateFormat: _dateFormat,
                  onOpenDirectory: _openDirectory,
                  onDownload: _enqueueDownload,
                  onCopyPath: _copyPath,
                );
                final queue = TransferQueuePanel(
                  items: _transfers,
                  onCancel: _cancelTransfer,
                  onRetry: _retryTransfer,
                  onOpen: _openDownloadedFile,
                );

                if (constraints.maxWidth >= 1200) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: list),
                      const SizedBox(width: AppSpacing.lg),
                      SizedBox(width: 360, child: queue),
                    ],
                  );
                }

                return Column(
                  children: [
                    Expanded(child: list),
                    const SizedBox(height: AppSpacing.lg),
                    queue,
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _connect(AppSettings settings) async {
    final profile = settings.sftpProfile;
    final root = normalizeVirtualPath(settings.sftpVirtualRoot, settings.sftpVirtualRoot);
    await _disconnect(clearMessage: true);
    setState(() {
      _status = _FilesStatus.connecting;
      _message = 'Connecting to ${profile.host}:${profile.port}';
      _currentPath = root;
    });

    try {
      final connection = await ref
          .read(sftpConnectionServiceProvider)
          .open(
            profile: profile,
            onTrustHost: (hostKey) => showHostTrustDialog(context, hostKey),
            onPassphraseRequired: () => showPassphrasePromptDialog(
              context,
              title: 'Enter the SFTP key passphrase',
            ),
          );
      _connection = connection;
      setState(() {
        _status = _FilesStatus.connected;
        _message = 'Connected to restricted SFTP root.';
      });
      await _loadDirectory(root);
    } catch (error) {
      setState(() {
        _status = _FilesStatus.error;
        _message = _describeError(error);
      });
    }
  }

  Future<void> _disconnect({
    String? message,
    bool clearMessage = false,
  }) async {
    _cancelOutstandingTransfers();
    final connection = _connection;
    _connection = null;
    if (connection != null) {
      await connection.close();
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _status = _FilesStatus.disconnected;
      _entries = const [];
      if (clearMessage) {
        _message = null;
      } else if (message != null) {
        _message = message;
      }
    });
  }

  Future<void> _loadDirectory(String requestedPath) async {
    final connection = _connection;
    if (connection == null) {
      return;
    }
    final settings = ref.read(settingsControllerProvider);
    final root = normalizeVirtualPath(settings.sftpVirtualRoot, settings.sftpVirtualRoot);
    final safePath = normalizeVirtualPath(root, requestedPath);

    try {
      final names = await connection.sftp.listdir(safePath);
      final entries = names
          .where((item) => item.filename != '.' && item.filename != '..')
          .map((item) {
            final attrs = item.attr;
            return RemoteFileEntry(
              name: item.filename,
              path: _joinPath(safePath, item.filename),
              isDirectory: attrs.isDirectory,
              isSymbolicLink: attrs.isSymbolicLink,
              sizeBytes: attrs.size,
              modifiedAt: attrs.modifyTime == null
                  ? null
                  : DateTime.fromMillisecondsSinceEpoch(
                      attrs.modifyTime! * 1000,
                    ),
            );
          })
          .toList(growable: false);
      if (!mounted) {
        return;
      }
      setState(() {
        _entries = entries;
        _currentPath = safePath;
        _status = _FilesStatus.connected;
        _message = 'Browsing $safePath';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = _FilesStatus.error;
        _message = _describeError(error);
      });
    }
  }

  Future<void> _openDirectory(RemoteFileEntry entry) async {
    if (entry.isSymbolicLink) {
      _showSnackBar('Symlink navigation is disabled.');
      return;
    }
    await _loadDirectory(entry.path);
  }

  Future<void> _goBack() async {
    final settings = ref.read(settingsControllerProvider);
    final root = normalizeVirtualPath(settings.sftpVirtualRoot, settings.sftpVirtualRoot);
    final current = _currentPath ?? root;
    if (current == root) {
      return;
    }
    final parts = current.split('/')..removeLast();
    final parent = parts.join('/');
    await _loadDirectory(parent.isEmpty ? root : parent);
  }

  void _enqueueDownload(RemoteFileEntry entry) {
    if (_connection == null) {
      _showSnackBar('Connect before downloading files.');
      return;
    }
    if (entry.isDirectory) {
      _showSnackBar('Directory downloads are not enabled.');
      return;
    }
    if (entry.isSymbolicLink) {
      _showSnackBar('Symlink downloads are disabled.');
      return;
    }

    final id = DateTime.now().microsecondsSinceEpoch.toString();
    _tokens[id] = DownloadCancellationToken();
    setState(() {
      _transfers = [
        ..._transfers,
        TransferItem(
          id: id,
          fileName: entry.name,
          remotePath: entry.path,
          localPath: null,
          totalBytes: entry.sizeBytes,
          transferredBytes: 0,
          state: TransferState.queued,
          errorMessage: null,
        ),
      ];
    });
    unawaited(_pumpQueue());
  }

  Future<void> _pumpQueue() async {
    if (_activeTransferId != null || _connection == null) {
      return;
    }
    final next = _transfers.cast<TransferItem?>().firstWhere(
      (item) => item?.state == TransferState.queued,
      orElse: () => null,
    );
    if (next == null) {
      return;
    }

    final connection = _connection!;
    final token = _tokens[next.id];
    if (token == null) {
      return;
    }

    _activeTransferId = next.id;
    _updateTransfer(
      next.id,
      (item) => item.copyWith(state: TransferState.downloading, clearError: true),
    );

    try {
      final result = await ref
          .read(fileDownloadServiceProvider)
          .download(
            sftp: connection.sftp,
            remotePath: next.remotePath,
            fileName: next.fileName,
            cancellationToken: token,
            onProgress: (transferredBytes, totalBytes, localPath) {
              if (!mounted) {
                return;
              }
              _updateTransfer(
                next.id,
                (item) => item.copyWith(
                  transferredBytes: transferredBytes,
                  totalBytes: totalBytes,
                  localPath: localPath,
                  state: TransferState.downloading,
                ),
              );
            },
          );
      _updateTransfer(
        next.id,
        (item) => item.copyWith(
          state: TransferState.completed,
          transferredBytes: result.transferredBytes,
          totalBytes: result.totalBytes,
          localPath: result.localPath,
          clearError: true,
        ),
      );
    } on DownloadCancelledException {
      _updateTransfer(
        next.id,
        (item) => item.copyWith(
          state: TransferState.cancelled,
          clearLocalPath: true,
          errorMessage: 'Download cancelled',
        ),
      );
    } catch (error) {
      _updateTransfer(
        next.id,
        (item) => item.copyWith(
          state: TransferState.failed,
          errorMessage: _describeError(error),
        ),
      );
    } finally {
      _tokens.remove(next.id);
      _activeTransferId = null;
      if (mounted) {
        unawaited(_pumpQueue());
      }
    }
  }

  void _cancelTransfer(TransferItem item) {
    final token = _tokens[item.id];
    if (token != null) {
      token.cancel();
    }
    if (item.state == TransferState.queued) {
      _updateTransfer(
        item.id,
        (current) => current.copyWith(
          state: TransferState.cancelled,
          errorMessage: 'Download cancelled',
        ),
      );
      _tokens.remove(item.id);
    }
  }

  void _retryTransfer(TransferItem item) {
    _tokens[item.id] = DownloadCancellationToken();
    _updateTransfer(
      item.id,
      (current) => current.copyWith(
        state: TransferState.queued,
        transferredBytes: 0,
        clearLocalPath: true,
        clearError: true,
      ),
    );
    unawaited(_pumpQueue());
  }

  Future<void> _openDownloadedFile(TransferItem item) async {
    final localPath = item.localPath;
    if (localPath == null) {
      return;
    }
    final result = await OpenFilex.open(localPath);
    if (!mounted) {
      return;
    }
    if (result.type != ResultType.done) {
      _showSnackBar(result.message);
    }
  }

  void _cancelOutstandingTransfers({bool mutateState = true}) {
    for (final token in _tokens.values) {
      token.cancel();
    }
    _tokens.clear();
    _activeTransferId = null;
    if (mutateState && _transfers.isNotEmpty && mounted) {
      setState(() {
        _transfers = [
          for (final item in _transfers)
            if (item.state == TransferState.completed)
              item
            else
              item.copyWith(
                state: TransferState.cancelled,
                errorMessage: 'Transfer queue cleared',
              ),
        ];
      });
    }
  }

  Future<void> _copyPath(String path) async {
    await Clipboard.setData(ClipboardData(text: path));
    _showSnackBar('Remote path copied.');
  }

  void _updateTransfer(
    String id,
    TransferItem Function(TransferItem item) update,
  ) {
    if (!mounted) {
      return;
    }
    setState(() {
      _transfers = [
        for (final item in _transfers)
          if (item.id == id) update(item) else item,
      ];
    });
  }

  List<RemoteFileEntry> _filteredEntries(
    List<RemoteFileEntry> entries,
    String query,
  ) {
    final trimmed = query.trim().toLowerCase();
    if (trimmed.isEmpty) {
      return entries;
    }
    return entries
        .where((item) => item.name.toLowerCase().contains(trimmed))
        .toList(growable: false);
  }

  List<RemoteFileEntry> _sortedEntries(List<RemoteFileEntry> entries) {
    final sorted = [...entries];
    sorted.sort((left, right) {
      if (left.isDirectory != right.isDirectory) {
        return left.isDirectory ? -1 : 1;
      }
      final primary = switch (_sort) {
        _FilesSort.name => left.name.toLowerCase().compareTo(right.name.toLowerCase()),
        _FilesSort.modified => _compareNullableDates(left.modifiedAt, right.modifiedAt),
        _FilesSort.size => (left.sizeBytes ?? -1).compareTo(right.sizeBytes ?? -1),
      };
      if (primary != 0) {
        return primary;
      }
      return left.name.toLowerCase().compareTo(right.name.toLowerCase());
    });
    return sorted;
  }

  int _compareNullableDates(DateTime? left, DateTime? right) {
    if (left == null && right == null) {
      return 0;
    }
    if (left == null) {
      return 1;
    }
    if (right == null) {
      return -1;
    }
    return right.compareTo(left);
  }

  String _joinPath(String base, String name) {
    if (base == '/') {
      return '/$name';
    }
    return '$base/$name';
  }

  String _describeError(Object error) {
    if (error is AppException) {
      return error.message;
    }
    return error.toString();
  }

  void _showSnackBar(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _RemoteFileList extends StatelessWidget {
  const _RemoteFileList({
    required this.entries,
    required this.currentPath,
    required this.dateFormat,
    required this.onOpenDirectory,
    required this.onDownload,
    required this.onCopyPath,
  });

  final List<RemoteFileEntry> entries;
  final String currentPath;
  final DateFormat dateFormat;
  final ValueChanged<RemoteFileEntry> onOpenDirectory;
  final ValueChanged<RemoteFileEntry> onDownload;
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
              : null,
          trailing: Wrap(
            spacing: AppSpacing.xs,
            children: [
              IconButton(
                tooltip: 'Copy remote path',
                onPressed: () => onCopyPath(entry.path),
                icon: const Icon(Icons.copy_all),
              ),
              if (!entry.isDirectory && !entry.isSymbolicLink)
                IconButton(
                  tooltip: 'Download file',
                  onPressed: () => onDownload(entry),
                  icon: const Icon(Icons.download),
                ),
            ],
          ),
        );
      },
    );
  }
}

enum _FilesStatus {
  disconnected('Disconnected', StatusTone.offline),
  connecting('Connecting', StatusTone.warning),
  connected('Connected', StatusTone.healthy),
  error('Blocked', StatusTone.critical);

  const _FilesStatus(this.label, this.tone);

  final String label;
  final StatusTone tone;
}

enum _FilesSort {
  name,
  modified,
  size,
}
