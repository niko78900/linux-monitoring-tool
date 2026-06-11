import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../domain/models/resource_state.dart';

class StaleBanner extends StatelessWidget {
  const StaleBanner({super.key, required this.states});

  final List<ResourceState<Object?>> states;

  @override
  Widget build(BuildContext context) {
    final stale = states.where((state) => state.isStale).toList();
    if (stale.isEmpty) {
      return const SizedBox.shrink();
    }
    final message = stale
        .map((state) => state.errorMessage)
        .whereType<String>()
        .toSet()
        .join(' | ');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.errorContainer.withValues(alpha: 0.3),
        border: Border.all(
          color: Theme.of(context).colorScheme.error.withValues(alpha: 0.4),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber, color: Theme.of(context).colorScheme.error),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Showing stale data. ${message.isEmpty ? 'Refresh failed.' : message}',
            ),
          ),
        ],
      ),
    );
  }
}
