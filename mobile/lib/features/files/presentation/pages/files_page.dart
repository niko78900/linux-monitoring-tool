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
import '../../../../core/security/secure_storage_service.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/path_safety.dart';
import '../../../../core/widgets/empty_state.dart';
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
import '../widgets/file_preview_dialogs.dart';
import '../widgets/files_search_sort_bar.dart';
import '../widgets/files_toolbar.dart';
import '../widgets/files_view_models.dart';
import '../widgets/recent_downloads_panel.dart';
import '../widgets/remote_file_list.dart';
import '../widgets/transfer_queue_panel.dart';
import '../../../terminal/domain/models/ssh_connection_models.dart';
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
  Timer? _backgroundDisconnectTimer;
  String? _activeTransferId;
  FilesSort _sort = FilesSort.name;
  bool _searchingRemote = false;
  int _connectAttemptId = 0;
  String? _autoConnectAttemptedForProfile;
  bool _autoConnectScheduled = false;
  bool _manuallyDisconnected = false;
  bool _backgroundDisconnected = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleAutoConnect();
  }

  @override
  void dispose() {
    _connectAttemptId += 1;
    WidgetsBinding.instance.removeObserver(this);
    _backgroundDisconnectTimer?.cancel();
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
      _handleBackgrounded();
      return;
    }
    if (state == AppLifecycleState.resumed) {
      final shouldReconnect = _backgroundDisconnected;
      _cancelBackgroundDisconnect();
      if (shouldReconnect && !_manuallyDisconnected) {
        _backgroundDisconnected = false;
        _autoConnectAttemptedForProfile = null;
        _scheduleAutoConnect(force: true);
      }
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

    _scheduleAutoConnect(settings: settings);

    final visibleEntries = _sortedEntries(
      _filteredEntries(_entries, _searchController.text),
    );

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilesToolbar(
            statusLabel: _status.label,
            statusTone: _status.tone,
            currentPath: _currentPath ?? root,
            message: _message,
            isConnecting: _status == _FilesStatus.connecting,
            isConnected: _connection != null,
            canDisconnect:
                _connection != null || _status == _FilesStatus.connecting,
            isFavorite: _isCurrentPathFavorite(hostProfileId),
            isSearchingRemote: _searchingRemote,
            canUpload: settings.allowSftpUpload,
            canCreateDirectory: settings.allowSftpCreateDirectory,
            favorites: _favorites,
            onConnect: () => _connect(settings),
            onDisconnect: () => _disconnect(userInitiated: true),
            onRoot: () => _loadDirectory(root),
            onBack: _goBack,
            onRefresh: () => _loadDirectory(_currentPath ?? root),
            onCopyCurrentPath: () => _copyPath(_currentPath ?? root),
            onToggleFavorite: () => _toggleFavorite(hostProfileId),
            onRemoteSearch: () => _promptRecursiveSearch(root),
            onUpload: () => _uploadFile(root),
            onCreateDirectory: () => _createDirectory(root),
            onOpenFavorite: _loadDirectory,
          ),
          if (_searchStatus != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(_searchStatus!),
          ],
          const SizedBox(height: AppSpacing.md),
          if (!canMutateFiles(settings))
            Text(
              'File writes remain disabled until enabled in Settings and supported by the restricted SFTP account.',
            ),
          const SizedBox(height: AppSpacing.md),
          FilesSearchSortBar(
            searchController: _searchController,
            sort: _sort,
            onSearchChanged: (_) => setState(() {}),
            onSortChanged: (value) => setState(() => _sort = value),
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final list = RemoteFileList(
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
                    RecentDownloadsPanel(
                      items: _recentDownloads,
                      onOpen: (item) => _openLocalPath(item.localPath),
                      onRemove: (item) =>
                          _removeRecentDownload(hostProfileId, item.remotePath),
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

  void _scheduleAutoConnect({AppSettings? settings, bool force = false}) {
    if (_autoConnectScheduled) {
      return;
    }
    if (settings != null &&
        !_canAutoConnect(
          settings,
          _autoConnectProfileKey(settings),
          force: force,
        )) {
      return;
    }
    _autoConnectScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoConnectScheduled = false;
      if (!mounted) {
        return;
      }
      final AppSettings currentSettings =
          settings ?? ref.read(settingsControllerProvider);
      unawaited(_maybeAutoConnect(currentSettings, force: force));
    });
  }

  Future<void> _maybeAutoConnect(
    AppSettings settings, {
    bool force = false,
  }) async {
    final profileKey = _autoConnectProfileKey(settings);
    if (!_canAutoConnect(settings, profileKey, force: force)) {
      return;
    }
    _autoConnectAttemptedForProfile = profileKey;
    await _connect(settings, automatic: true);
  }

  bool _canAutoConnect(
    AppSettings settings,
    String profileKey, {
    required bool force,
  }) {
    final profile = settings.sftpProfile;
    return profile.isConfigured &&
        profile.hasImportedKey &&
        _connection == null &&
        _status != _FilesStatus.connecting &&
        !_manuallyDisconnected &&
        (force || _autoConnectAttemptedForProfile != profileKey);
  }

  String _autoConnectProfileKey(AppSettings settings) {
    final profile = settings.sftpProfile;
    return [
      profile.host.trim(),
      profile.port.toString(),
      profile.username.trim(),
      settings.sftpVirtualRoot.trim(),
      profile.hasImportedKey.toString(),
      profile.storePassphrase.toString(),
    ].join('|');
  }

  Future<void> _connect(AppSettings settings, {bool automatic = false}) async {
    if (automatic &&
        !_canAutoConnect(
          settings,
          _autoConnectProfileKey(settings),
          force: true,
        )) {
      return;
    }
    if (!automatic) {
      _manuallyDisconnected = false;
      _backgroundDisconnected = false;
      _autoConnectAttemptedForProfile = _autoConnectProfileKey(settings);
    }
    _backgroundDisconnectTimer?.cancel();
    final profile = settings.sftpProfile;
    final root = normalizeVirtualPath(
      settings.sftpVirtualRoot,
      settings.sftpVirtualRoot,
    );
    await _disconnect(clearMessage: true);
    final attemptId = ++_connectAttemptId;
    if (!mounted || attemptId != _connectAttemptId) {
      return;
    }
    setState(() {
      _status = _FilesStatus.connecting;
      _message = automatic
          ? 'Auto-connecting to ${profile.host}:${profile.port}'
          : 'Connecting to ${profile.host}:${profile.port}';
      _currentPath = root;
    });

    try {
      final connection = await ref
          .read(sftpConnectionServiceProvider)
          .open(
            profile: profile,
            onTrustHost: (hostKey) => showHostTrustDialog(context, hostKey),
            onPassphraseRequired: _promptPassphrase,
          );
      if (!mounted || attemptId != _connectAttemptId) {
        await connection.close();
        return;
      }
      _connection = connection;
      setState(() {
        _status = _FilesStatus.connected;
        _message = 'Connected to restricted SFTP root.';
      });
      _backgroundDisconnected = false;
      await _refreshMetadata();
      if (!mounted ||
          attemptId != _connectAttemptId ||
          !identical(_connection, connection)) {
        return;
      }
      await _loadDirectory(root);
    } catch (error) {
      if (!mounted || attemptId != _connectAttemptId) {
        return;
      }
      setState(() {
        _status = _FilesStatus.error;
        _message = _describeError(error);
      });
    }
  }

  Future<void> _disconnect({
    String? message,
    bool clearMessage = false,
    bool userInitiated = false,
    bool backgroundTimeout = false,
  }) async {
    _connectAttemptId += 1;
    if (userInitiated) {
      _manuallyDisconnected = true;
      _backgroundDisconnected = false;
    } else if (backgroundTimeout) {
      _backgroundDisconnected = true;
    }
    _backgroundDisconnectTimer?.cancel();
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

  Future<PassphrasePromptResult?> _promptPassphrase() async {
    if (!mounted) {
      return null;
    }
    final settings = ref.read(settingsControllerProvider);
    final result = await showPassphrasePromptDialog(
      context,
      title: 'Enter the SFTP key passphrase',
      rememberInitially: settings.sftpProfile.storePassphrase,
    );
    if (result == null) {
      return null;
    }
    if (!mounted) {
      return null;
    }

    final storage = ref.read(secureStorageServiceProvider);
    if (result.remember) {
      await storage.writeSftpPassphrase(result.passphrase);
      ref
          .read(settingsControllerProvider.notifier)
          .save(
            settings.copyWith(
              sftpProfile: settings.sftpProfile.copyWith(storePassphrase: true),
            ),
          );
    } else {
      await storage.clearSftpPassphrase();
      if (settings.sftpProfile.storePassphrase) {
        ref
            .read(settingsControllerProvider.notifier)
            .save(
              settings.copyWith(
                sftpProfile: settings.sftpProfile.copyWith(
                  storePassphrase: false,
                ),
              ),
            );
      }
    }
    return result;
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

  Future<void> _openEntryExternally(RemoteFileEntry entry) async {
    if (entry.isDirectory || entry.isSymbolicLink) {
      _showSnackBar('External open is only available for regular files.');
      return;
    }
    final connection = _connection;
    if (connection == null) {
      _showSnackBar('Connect before opening files.');
      return;
    }
    final previewService = ref.read(filePreviewServiceProvider);
    try {
      _showSnackBar('Opening ${entry.name} with a system app...');
      final path = await previewService.cacheRemoteFile(
        sftp: connection.sftp,
        remotePath: entry.path,
        fileName: entry.name,
        sizeBytes: entry.sizeBytes,
      );
      await _openLocalPath(path);
    } catch (error) {
      _showSnackBar(_describeError(error));
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
        await showImagePreviewDialog(context, localPath: path);
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
        await showTextPreviewDialog(
          context,
          title: entry.name,
          text: text,
          onCopied: () => _showSnackBar('Preview text copied.'),
        );
        return;
      }

      if (isExternalPreviewable(entry.name)) {
        await _openEntryExternally(entry);
        return;
      }

      if (isVideoPreviewable(entry.name)) {
        await _openEntryExternally(entry);
        return;
      }

      await _showUnsupportedPreviewDialog(entry);
    } catch (error) {
      _showSnackBar(_describeError(error));
    }
  }

  void _handleBackgrounded() {
    if (_connection == null) {
      if (_status == _FilesStatus.connecting) {
        _connectAttemptId += 1;
        if (mounted) {
          setState(() {
            _status = _FilesStatus.disconnected;
            _message = 'SFTP connection cancelled in background.';
          });
        }
      }
      return;
    }
    final timeout = ref.read(settingsControllerProvider).sftpBackgroundTimeout;
    _backgroundDisconnectTimer?.cancel();
    if (timeout == SftpBackgroundTimeout.immediate) {
      unawaited(
        _disconnect(
          message: 'SFTP session closed after the app moved to background.',
          backgroundTimeout: true,
        ),
      );
      return;
    }
    final duration = timeout.duration;
    if (duration == null) {
      if (mounted) {
        setState(() {
          _message = 'SFTP remains connected in background.';
        });
      }
      return;
    }
    if (mounted) {
      setState(() {
        _status = _FilesStatus.backgroundPending;
        _message = 'Background disconnect scheduled in ${timeout.label}.';
      });
    }
    _backgroundDisconnectTimer = Timer(duration, () {
      unawaited(
        _disconnect(
          message: 'SFTP disconnected after ${timeout.label} in background.',
          backgroundTimeout: true,
        ),
      );
    });
  }

  void _cancelBackgroundDisconnect() {
    final hadTimer = _backgroundDisconnectTimer != null;
    _backgroundDisconnectTimer?.cancel();
    _backgroundDisconnectTimer = null;
    if (hadTimer && mounted && _connection != null) {
      setState(() {
        _status = _FilesStatus.connected;
        _message = 'SFTP background timeout cancelled.';
      });
    }
  }

  Future<void> _showUnsupportedPreviewDialog(RemoteFileEntry entry) async {
    await showUnsupportedPreviewDialog(
      context,
      entry: entry,
      onCopyPath: () => _copyPath(entry.path),
      onDownload: () => _enqueueDownload(entry),
      onOpenExternally: () => _openEntryExternally(entry),
    );
  }

  Future<void> _promptRecursiveSearch(String root) async {
    final query = await showRemoteSearchPrompt(
      context,
      initialQuery: _searchController.text,
    );
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
      await showRemoteSearchResultsDialog(
        context,
        results: snapshot.results,
        onOpenDirectory: _loadDirectory,
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
    final name = await showTextInputDialog(
      context,
      title: 'Create directory',
      labelText: 'Directory name',
      confirmLabel: 'Create',
    );
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
    FileEntryAction action,
    String root,
  ) async {
    final settings = ref.read(settingsControllerProvider);
    final connection = _connection;
    if (connection == null) {
      return;
    }

    switch (action) {
      case FileEntryAction.preview:
        await _previewEntry(entry);
      case FileEntryAction.openExternal:
        await _openEntryExternally(entry);
      case FileEntryAction.download:
        _enqueueDownload(entry);
      case FileEntryAction.rename:
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
      case FileEntryAction.move:
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
      case FileEntryAction.softDelete:
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
    return showTextInputDialog(
      context,
      title: title,
      initialValue: initialValue,
    );
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
        FilesSort.name => left.name.toLowerCase().compareTo(
          right.name.toLowerCase(),
        ),
        FilesSort.modified => _compareNullableDates(
          left.modifiedAt,
          right.modifiedAt,
        ),
        FilesSort.size => (left.sizeBytes ?? -1).compareTo(
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

enum _FilesStatus {
  disconnected('Disconnected', StatusTone.offline),
  connecting('Connecting', StatusTone.warning),
  connected('Connected', StatusTone.healthy),
  backgroundPending('Background timeout pending', StatusTone.warning),
  error('Blocked', StatusTone.critical);

  const _FilesStatus(this.label, this.tone);

  final String label;
  final StatusTone tone;
}
