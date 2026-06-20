import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../../core/widgets/status_tone.dart';
import '../../domain/models/file_browser_models.dart';

class FilesToolbar extends StatelessWidget {
  const FilesToolbar({
    super.key,
    required this.statusLabel,
    required this.statusTone,
    required this.currentPath,
    required this.message,
    required this.isConnecting,
    required this.isConnected,
    required this.canDisconnect,
    required this.isFavorite,
    required this.isSearchingRemote,
    required this.canUpload,
    required this.canCreateDirectory,
    required this.favorites,
    required this.onConnect,
    required this.onDisconnect,
    required this.onRoot,
    required this.onBack,
    required this.onRefresh,
    required this.onCopyCurrentPath,
    required this.onToggleFavorite,
    required this.onRemoteSearch,
    required this.onUpload,
    required this.onCreateDirectory,
    required this.onOpenFavorite,
  });

  final String statusLabel;
  final StatusTone statusTone;
  final String currentPath;
  final String? message;
  final bool isConnecting;
  final bool isConnected;
  final bool canDisconnect;
  final bool isFavorite;
  final bool isSearchingRemote;
  final bool canUpload;
  final bool canCreateDirectory;
  final List<FavoriteLocation> favorites;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;
  final VoidCallback onRoot;
  final VoidCallback onBack;
  final VoidCallback onRefresh;
  final VoidCallback onCopyCurrentPath;
  final VoidCallback onToggleFavorite;
  final VoidCallback onRemoteSearch;
  final VoidCallback onUpload;
  final VoidCallback onCreateDirectory;
  final ValueChanged<String> onOpenFavorite;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            StatusBadge(label: statusLabel, tone: statusTone),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Text(currentPath),
            ),
            if (message != null)
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Text(message!),
              ),
            FilledButton.icon(
              onPressed: isConnecting ? null : onConnect,
              icon: const Icon(Icons.folder_open),
              label: Text(isConnected ? 'Reconnect' : 'Connect'),
            ),
            OutlinedButton.icon(
              onPressed: canDisconnect ? onDisconnect : null,
              icon: const Icon(Icons.link_off),
              label: Text(isConnecting ? 'Cancel' : 'Disconnect'),
            ),
            OutlinedButton.icon(
              onPressed: isConnected ? onRoot : null,
              icon: const Icon(Icons.home),
              label: const Text('Root'),
            ),
            OutlinedButton.icon(
              onPressed: isConnected ? onBack : null,
              icon: const Icon(Icons.arrow_upward),
              label: const Text('Back'),
            ),
            IconButton(
              tooltip: 'Refresh',
              onPressed: isConnected ? onRefresh : null,
              icon: const Icon(Icons.refresh),
            ),
            IconButton(
              tooltip: 'Copy remote path',
              onPressed: onCopyCurrentPath,
              icon: const Icon(Icons.copy_all),
            ),
            OutlinedButton.icon(
              onPressed: isConnected ? onToggleFavorite : null,
              icon: Icon(isFavorite ? Icons.star : Icons.star_border),
              label: Text(isFavorite ? 'Unfavorite' : 'Favorite'),
            ),
            OutlinedButton.icon(
              onPressed: isConnected && !isSearchingRemote
                  ? onRemoteSearch
                  : null,
              icon: const Icon(Icons.manage_search),
              label: Text(isSearchingRemote ? 'Searching...' : 'Remote Search'),
            ),
            OutlinedButton.icon(
              onPressed: isConnected && canUpload ? onUpload : null,
              icon: const Icon(Icons.upload_file),
              label: const Text('Upload'),
            ),
            OutlinedButton.icon(
              onPressed: isConnected && canCreateDirectory
                  ? onCreateDirectory
                  : null,
              icon: const Icon(Icons.create_new_folder),
              label: const Text('New Folder'),
            ),
          ],
        ),
        if (favorites.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final favorite in favorites)
                ActionChip(
                  avatar: const Icon(Icons.star, size: 18),
                  label: Text(favorite.remotePath),
                  onPressed: isConnected
                      ? () => onOpenFavorite(favorite.remotePath)
                      : null,
                ),
            ],
          ),
        ],
      ],
    );
  }
}
