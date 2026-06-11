import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/byte_format.dart';
import '../../../../core/widgets/section_card.dart';
import '../../domain/models/transfer_item.dart';

class TransferQueuePanel extends StatelessWidget {
  const TransferQueuePanel({
    super.key,
    required this.items,
    required this.onCancel,
    required this.onRetry,
    required this.onOpen,
  });

  final List<TransferItem> items;
  final ValueChanged<TransferItem> onCancel;
  final ValueChanged<TransferItem> onRetry;
  final ValueChanged<TransferItem> onOpen;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Transfer Queue',
      child: items.isEmpty
          ? const Text('No downloads queued.')
          : Column(
              children: [
                for (final item in items) ...[
                  _TransferRow(
                    item: item,
                    onCancel: () => onCancel(item),
                    onRetry: () => onRetry(item),
                    onOpen: () => onOpen(item),
                  ),
                  if (item != items.last)
                    const Divider(height: AppSpacing.lg),
                ],
              ],
            ),
    );
  }
}

class _TransferRow extends StatelessWidget {
  const _TransferRow({
    required this.item,
    required this.onCancel,
    required this.onRetry,
    required this.onOpen,
  });

  final TransferItem item;
  final VoidCallback onCancel;
  final VoidCallback onRetry;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final progress = item.progress;
    final progressText = switch (item.totalBytes) {
      null => formatBytes(item.transferredBytes),
      final total => '${formatBytes(item.transferredBytes)} / ${formatBytes(total)}',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                item.fileName,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            Text(_stateLabel(item.state)),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        SelectableText(item.remotePath),
        if (item.localPath != null) ...[
          const SizedBox(height: AppSpacing.xs),
          SelectableText(item.localPath!),
        ],
        const SizedBox(height: AppSpacing.sm),
        if (progress != null)
          LinearProgressIndicator(value: progress)
        else if (item.state == TransferState.downloading)
          const LinearProgressIndicator(),
        const SizedBox(height: AppSpacing.xs),
        Text(progressText),
        if (item.errorMessage != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            item.errorMessage!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            if (item.state == TransferState.queued ||
                item.state == TransferState.downloading)
              OutlinedButton(
                onPressed: onCancel,
                child: const Text('Cancel'),
              ),
            if (item.state == TransferState.failed ||
                item.state == TransferState.cancelled)
              OutlinedButton(
                onPressed: onRetry,
                child: const Text('Retry'),
              ),
            if (item.state == TransferState.completed && item.localPath != null)
              FilledButton(
                onPressed: onOpen,
                child: const Text('Open file'),
              ),
          ],
        ),
      ],
    );
  }

  String _stateLabel(TransferState state) {
    return switch (state) {
      TransferState.queued => 'Queued',
      TransferState.downloading => 'Downloading',
      TransferState.completed => 'Completed',
      TransferState.failed => 'Failed',
      TransferState.cancelled => 'Cancelled',
    };
  }
}
