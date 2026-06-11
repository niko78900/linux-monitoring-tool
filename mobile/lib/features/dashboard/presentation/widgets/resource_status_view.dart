import 'package:flutter/material.dart';

import '../../../../core/widgets/empty_state.dart';
import '../../domain/models/resource_state.dart';

class ResourceStatusView<T> extends StatelessWidget {
  const ResourceStatusView({
    super.key,
    required this.state,
    required this.builder,
    this.emptyTitle = 'No data yet',
    this.emptyMessage = 'The server has not returned this payload yet.',
    this.onRetry,
  });

  final ResourceState<T> state;
  final Widget Function(T data) builder;
  final String emptyTitle;
  final String emptyMessage;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final data = state.data;
    if (data != null) {
      return builder(data);
    }
    if (state.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return EmptyState(
      icon: Icons.cloud_off,
      title: state.errorMessage ?? emptyTitle,
      message: emptyMessage,
      action: onRetry == null
          ? null
          : FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
    );
  }
}
