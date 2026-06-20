import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/section_card.dart';
import '../../domain/models/file_browser_models.dart';

class RecentDownloadsPanel extends StatelessWidget {
  const RecentDownloadsPanel({
    super.key,
    required this.items,
    required this.onOpen,
    required this.onRemove,
  });

  final List<RecentDownloadRecord> items;
  final ValueChanged<RecentDownloadRecord> onOpen;
  final ValueChanged<RecentDownloadRecord> onRemove;

  @override
  Widget build(BuildContext context) {
    final visibleItems = items.take(5).toList(growable: false);
    return SectionCard(
      title: 'Recent Downloads',
      child: visibleItems.isEmpty
          ? const Text('No recent downloads')
          : Column(
              children: [
                for (final item in visibleItems) ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(item.fileName),
                    subtitle: Text(item.remotePath),
                    trailing: Wrap(
                      spacing: AppSpacing.xs,
                      children: [
                        IconButton(
                          tooltip: 'Open',
                          onPressed: () => onOpen(item),
                          icon: const Icon(Icons.open_in_new),
                        ),
                        IconButton(
                          tooltip: 'Remove from recents',
                          onPressed: () => onRemove(item),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  if (item != visibleItems.last) const Divider(height: 1),
                ],
              ],
            ),
    );
  }
}
