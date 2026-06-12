import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:file_picker/file_picker.dart';
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
import '../../../../core/widgets/section_card.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../../core/widgets/status_tone.dart';
import '../../data/file_browser_utils.dart';
import '../../data/file_download_service.dart';
import '../../data/file_metadata_store.dart';
import '../../data/file_preview_service.dart';
import '../../data/file_search_service.dart';
import '../../data/sftp_connection_service.dart';
import '../../domain/models/file_browser_models.dart';
import '../../domain/models/remote_file_entry.dart';
import '../../domain/models/transfer_item.dart';
import '../widgets/transfer_queue_panel.dart';
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
  String? _searchStatus;
  String? _currentPath;
  List<RemoteFileEntry> _entries = const [];
  List<TransferItem> _transfers = const [];
  List<FavoriteLocation> _favorites = const [];
  List<RecentDownloadRecord> _recentDownloads = const [];
  final Map<String, DownloadCancellationToken> _tokens =
      <String, DownloadCancellationToken>{};
  String? _activeTransferId;
  _FilesSort _sort = _FilesSort.name;
  bool _searchingRemote = false;

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
        _disconnect(
          message: 'SFTP session closed after the app moved to background.',
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsControllerProvider);
    final profile = settings.sftpProfile;
    final root = normalizeVirtualPath(
      settings.sftpVirtualRoot,
      settings.sftpVirtualRoot,
    );
    final hostProfileId = buildSftpProfileId(profile);

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
                onPressed: _connection == null
                    ? null
                    : () => _loadDirectory(root),
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
              OutlinedButton.icon(
                onPressed: _connection == null
                    ? null
                    : () => _toggleFavorite(hostProfileId),
                icon: Icon(
                  _isCurrentPathFavorite(hostProfileId)
                      ? Icons.star
                      : Icons.star_border,
                ),
                label: Text(
                  _isCurrentPathFavorite(hostProfileId)
                      ? 'Unfavorite'
                      : 'Favorite',
                ),
              ),
              OutlinedButton.icon(
                onPressed: _connection == null || _searchingRemote
                    ? null
                    : () => _promptRecursiveSearch(root),
                icon: const Icon(Icons.manage_search),
                label: Text(
                  _searchingRemote ? 'Searching...' : 'Remote Search',
                ),
              ),
              OutlinedButton.icon(
                onPressed: _connection == null || !settings.allowSftpUpload
                    ? null
                    : () => _uploadFile(root),
                icon: const Icon(Icons.upload_file),
                label: const Text('Upload'),
              ),
              OutlinedButton.icon(
                onPressed:
                    _connection == null || !settings.allowSftpCreateDirectory
                    ? null
                    : () => _createDirectory(root),
                icon: const Icon(Icons.create_new_folder),
                label: const Text('New Folder'),
              ),
            ],
          ),
          if (_searchStatus != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(_searchStatus!),
          ],
          if (_favorites.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final favorite in _favorites)
                  ActionChip(
                    avatar: const Icon(Icons.star, size: 18),
                    label: Text(favorite.remotePath),
                    onPressed: _connection == null
                        ? null
                        : () => _loadDirectory(favorite.remotePath),
                  ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          if (!canMutateFiles(settings))
            Text(
              'File writes remain disabled until enabled in Settings and supported by the restricted SFTP account.',
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
                  onPreview: _previewEntry,
                  onDownload: _enqueueDownload,
                  onEntryAction: (entry, action) =>
                      _handleEntryAction(entry, action, root),
                  onCopyPath: _copyPath,
                );

                final queue = Column(
                  children: [
                    TransferQueuePanel(
                      items: _transfers,
                      onCancel: _cancelTransfer,
                      onRetry: _retryTransfer,
                      onOpen: _openDownloadedFile,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    SectionCard(
                      title: 'Recent Downloads',
                      child: _recentDownloads.isEmpty
                          ? const Text('No recent downloads')
                          : Column(
                              children: [
                                for (final item in _recentDownloads.take(
                                  5,
                                )) ...[
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(item.fileName),
                                    subtitle: Text(item.remotePath),
                                    trailing: Wrap(
                                      spacing: AppSpacing.xs,
                                      children: [
                                        IconButton(
                                          tooltip: 'Open',
                                          onPressed: () =>
                                              _openLocalPath(item.localPath),
                                          icon: const Icon(Icons.open_in_new),
                                        ),
                                        IconButton(
                                          tooltip: 'Remove from recents',
                                          onPressed: () =>
                                              _removeRecentDownload(
                                                hostProfileId,
                                                item.remotePath,
                                              ),
                                          icon: const Icon(Icons.close),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (item != _recentDownloads.take(5).last)
                                    const Divider(height: 1),
                                ],
                              ],
                            ),
                    ),
                  ],
                );

                if (constraints.maxWidth >= 1200) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: list),
                      const SizedBox(width: AppSpacing.lg),
                      SizedBox(width: 380, child: queue),
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
    final root = normalizeVirtualPath(
      settings.sftpVirtualRoot,
      settings.sftpVirtualRoot,
    );
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
      await _refreshMetadata();
      await _loadDirectory(root);
    } catch (error) {
      setState(() {
        _status = _FilesStatus.error;
        _message = _describeError(error);
      });
    }
  }

  Future<void> _disconnect({String? message, bool clearMessage = false}) async {
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
    final root = normalizeVirtualPath(
      settings.sftpVirtualRoot,
      settings.sftpVirtualRoot,
    );
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
      await _refreshMetadata();
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
    final root = normalizeVirtualPath(
      settings.sftpVirtualRoot,
      settings.sftpVirtualRoot,
    );
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

    final entry = _entries.cast<RemoteFileEntry?>().firstWhere(
      (item) => item?.path == next.remotePath,
      orElse: () => null,
    );
    final profile = ref.read(settingsControllerProvider).sftpProfile;
    final hostProfileId = buildSftpProfileId(profile);

    _activeTransferId = next.id;
    _updateTransfer(
      next.id,
      (item) =>
          item.copyWith(state: TransferState.downloading, clearError: true),
    );

    try {
      final result = await ref
          .read(fileDownloadServiceProvider)
          .download(
            sftp: connection.sftp,
            hostProfileId: hostProfileId,
            remotePath: next.remotePath,
            fileName: next.fileName,
            remoteModifiedAt: entry?.modifiedAt?.toUtc(),
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
      await ref
          .read(fileMetadataStoreProvider)
          .upsertRecentDownload(
            RecentDownloadRecord(
              hostProfileId: hostProfileId,
              fileName: result.fileName,
              remotePath: next.remotePath,
              localPath: result.localPath,
              sizeBytes: result.totalBytes,
              remoteModifiedAt: entry?.modifiedAt?.toUtc(),
              downloadedAt: DateTime.now().toUtc(),
            ),
          );
      await _refreshMetadata();
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
    await _openLocalPath(localPath);
  }

  Future<void> _openLocalPath(String localPath) async {
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

  Future<void> _refreshMetadata() async {
    final profile = ref.read(settingsControllerProvider).sftpProfile;
    final hostProfileId = buildSftpProfileId(profile);
    final store = ref.read(fileMetadataStoreProvider);
    final favorites = await store.listFavorites(hostProfileId);
    final recents = await store.listRecentDownloads(hostProfileId);
    if (!mounted) {
      return;
    }
    setState(() {
      _favorites = favorites;
      _recentDownloads = recents;
    });
  }

  bool _isCurrentPathFavorite(String hostProfileId) {
    final currentPath = _currentPath;
    if (currentPath == null) {
      return false;
    }
    return _favorites.any(
      (favorite) =>
          favorite.hostProfileId == hostProfileId &&
          favorite.remotePath == currentPath,
    );
  }

  Future<void> _toggleFavorite(String hostProfileId) async {
    final currentPath = _currentPath;
    if (currentPath == null) {
      return;
    }
    final store = ref.read(fileMetadataStoreProvider);
    if (_isCurrentPathFavorite(hostProfileId)) {
      await store.removeFavorite(hostProfileId, currentPath);
    } else {
      await store.addFavorite(hostProfileId, currentPath);
    }
    await _refreshMetadata();
  }

  Future<void> _removeRecentDownload(
    String hostProfileId,
    String remotePath,
  ) async {
    await ref
        .read(fileMetadataStoreProvider)
        .removeRecentDownload(hostProfileId, remotePath);
    await _refreshMetadata();
  }

  Future<void> _previewEntry(RemoteFileEntry entry) async {
    if (entry.isDirectory || _connection == null) {
      return;
    }
    final previewService = ref.read(filePreviewServiceProvider);
    try {
      if (isImagePreviewable(entry.name)) {
        final path = await previewService.cacheRemoteFile(
          sftp: _connection!.sftp,
          remotePath: entry.path,
          fileName: entry.name,
          sizeBytes: entry.sizeBytes,
        );
        if (!mounted) {
          return;
        }
        await showDialog<void>(
          context: context,
          builder: (context) =>
              Dialog(child: InteractiveViewer(child: Image.file(File(path)))),
        );
        return;
      }

      if (isTextPreviewable(entry.name)) {
        final sizeBytes = entry.sizeBytes ?? 0;
        final text = await previewService.readTextPreview(
          sftp: _connection!.sftp,
          remotePath: entry.path,
          sizeBytes: sizeBytes,
        );
        if (!mounted) {
          return;
        }
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(entry.name),
            content: SizedBox(
              width: 720,
              child: SingleChildScrollView(child: SelectableText(text)),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        );
        return;
      }

      if (isVideoPreviewable(entry.name)) {
        final path = await previewService.cacheRemoteFile(
          sftp: _connection!.sftp,
          remotePath: entry.path,
          fileName: entry.name,
          sizeBytes: entry.sizeBytes,
        );
        await _openLocalPath(path);
        return;
      }

      _showSnackBar('Preview is unavailable for this file type.');
    } catch (error) {
      _showSnackBar(_describeError(error));
    }
  }

  Future<void> _promptRecursiveSearch(String root) async {
    final controller = TextEditingController(text: _searchController.text);
    final query = await showDialog<String>(
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
    controller.dispose();
    final trimmed = query?.trim() ?? '';
    if (trimmed.isEmpty || _connection == null) {
      return;
    }

    final token = FileSearchCancellationToken();
    setState(() {
      _searchingRemote = true;
      _searchStatus = 'Searching recursively from ${_currentPath ?? root}';
    });
    try {
      final snapshot = await ref
          .read(fileSearchServiceProvider)
          .search(
            sftp: _connection!.sftp,
            virtualRoot: root,
            startPath: _currentPath ?? root,
            query: trimmed,
            cancellationToken: token,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _searchStatus = snapshot.truncated
            ? 'Search truncated at ${snapshot.results.length} results.'
            : 'Search completed with ${snapshot.results.length} results.';
      });
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Search results'),
          content: SizedBox(
            width: 720,
            child: snapshot.results.isEmpty
                ? const Text('No results found.')
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: snapshot.results.length,
                    itemBuilder: (context, index) {
                      final result = snapshot.results[index];
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
                            _loadDirectory(result.entryPath);
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
    } catch (error) {
      if (mounted) {
        setState(() => _searchStatus = _describeError(error));
      }
    } finally {
      if (mounted) {
        setState(() => _searchingRemote = false);
      }
    }
  }

  Future<void> _uploadFile(String root) async {
    final connection = _connection;
    if (connection == null) {
      return;
    }
    final result = await FilePicker.pickFiles();
    if (result == null || result.files.single.path == null) {
      return;
    }
    final selected = File(result.files.single.path!);
    final fileName = selected.uri.pathSegments.last;
    final currentPath = _currentPath ?? root;
    final temporaryRemote = '$currentPath/$fileName.uploading';
    final finalRemote = '$currentPath/$fileName';
    final remoteFile = await connection.sftp.open(
      temporaryRemote,
      mode:
          SftpFileOpenMode.create |
          SftpFileOpenMode.truncate |
          SftpFileOpenMode.write,
    );
    try {
      await remoteFile.write(selected.openRead().cast()).done;
      await remoteFile.close();
      await connection.sftp.rename(temporaryRemote, finalRemote);
      _showSnackBar('Upload completed.');
      await _loadDirectory(currentPath);
    } catch (error) {
      await remoteFile.close();
      _showSnackBar(_describeError(error));
    }
  }

  Future<void> _createDirectory(String root) async {
    final connection = _connection;
    if (connection == null) {
      return;
    }
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create directory'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Directory name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    controller.dispose();
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty) {
      return;
    }
    final currentPath = _currentPath ?? root;
    final target = normalizeVirtualPath(root, '$currentPath/$trimmed');
    await connection.sftp.mkdir(target);
    await _loadDirectory(currentPath);
  }

  Future<void> _handleEntryAction(
    RemoteFileEntry entry,
    _EntryAction action,
    String root,
  ) async {
    final settings = ref.read(settingsControllerProvider);
    final connection = _connection;
    if (connection == null) {
      return;
    }

    switch (action) {
      case _EntryAction.preview:
        await _previewEntry(entry);
      case _EntryAction.download:
        _enqueueDownload(entry);
      case _EntryAction.rename:
        if (!settings.allowSftpRename) {
          _showSnackBar('Rename is disabled in Settings.');
          return;
        }
        final newName = await _promptForText(
          'Rename ${entry.name}',
          entry.name,
        );
        if (newName == null || newName.trim().isEmpty) {
          return;
        }
        final baseSegments = entry.path.split('/')..removeLast();
        final target = normalizeVirtualPath(
          root,
          '${baseSegments.join('/')}/$newName',
        );
        await connection.sftp.rename(entry.path, target);
        await _loadDirectory(_currentPath ?? root);
      case _EntryAction.move:
        if (!settings.allowSftpMove) {
          _showSnackBar('Move is disabled in Settings.');
          return;
        }
        final destination = await _promptForText(
          'Move ${entry.name}',
          _currentPath ?? root,
        );
        if (destination == null || destination.trim().isEmpty) {
          return;
        }
        final target = normalizeVirtualPath(
          root,
          '${destination.trim()}/${entry.name}',
        );
        await connection.sftp.rename(entry.path, target);
        await _loadDirectory(_currentPath ?? root);
      case _EntryAction.softDelete:
        if (!settings.allowSftpSoftDelete) {
          _showSnackBar('Soft delete is disabled in Settings.');
          return;
        }
        final trashRoot = normalizeVirtualPath(root, '$root/.tablet-trash');
        try {
          await connection.sftp.mkdir(trashRoot);
        } catch (_) {
          // Directory may already exist.
        }
        final target = buildSoftDeletePath(
          virtualRoot: root,
          sourcePath: entry.path,
          now: DateTime.now().toUtc(),
        );
        await connection.sftp.rename(entry.path, target);
        await _loadDirectory(_currentPath ?? root);
    }
  }

  Future<String?> _promptForText(String title, String initialValue) async {
    final controller = TextEditingController(text: initialValue);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
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
        _FilesSort.name => left.name.toLowerCase().compareTo(
          right.name.toLowerCase(),
        ),
        _FilesSort.modified => _compareNullableDates(
          left.modifiedAt,
          right.modifiedAt,
        ),
        _FilesSort.size => (left.sizeBytes ?? -1).compareTo(
          right.sizeBytes ?? -1,
        ),
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
  final void Function(RemoteFileEntry entry, _EntryAction action) onEntryAction;
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
                      : () => onEntryAction(entry, _EntryAction.preview),
                  icon: const Icon(Icons.visibility),
                ),
              if (!entry.isDirectory && !entry.isSymbolicLink)
                IconButton(
                  tooltip: 'Download file',
                  onPressed: () => onDownload(entry),
                  icon: const Icon(Icons.download),
                ),
              PopupMenuButton<_EntryAction>(
                onSelected: (action) => onEntryAction(entry, action),
                itemBuilder: (context) => [
                  if (!entry.isDirectory && !entry.isSymbolicLink)
                    const PopupMenuItem(
                      value: _EntryAction.preview,
                      child: Text('Preview'),
                    ),
                  const PopupMenuItem(
                    value: _EntryAction.rename,
                    child: Text('Rename'),
                  ),
                  const PopupMenuItem(
                    value: _EntryAction.move,
                    child: Text('Move'),
                  ),
                  const PopupMenuItem(
                    value: _EntryAction.softDelete,
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

enum _FilesStatus {
  disconnected('Disconnected', StatusTone.offline),
  connecting('Connecting', StatusTone.warning),
  connected('Connected', StatusTone.healthy),
  error('Blocked', StatusTone.critical);

  const _FilesStatus(this.label, this.tone);

  final String label;
  final StatusTone tone;
}

enum _FilesSort { name, modified, size }

enum _EntryAction { preview, download, rename, move, softDelete }
