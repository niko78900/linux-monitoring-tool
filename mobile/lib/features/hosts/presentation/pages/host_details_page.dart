import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/section_card.dart';
import '../providers/host_providers.dart';
import 'hosts_page.dart';

class HostDetailsPage extends ConsumerWidget {
  const HostDetailsPage({super.key, required this.hostId});

  final String hostId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hostState = ref.watch(managedHostProvider(hostId));
    return hostState.when(
      data: (host) => ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              IconButton(
                tooltip: 'Back',
                onPressed: () => context.go('/hosts'),
                icon: const Icon(Icons.arrow_back),
              ),
              Text(
                host.displayName,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              HostStatusBadge(host: host),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          SectionCard(
            title: 'Host',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (host.description != null &&
                    host.description!.trim().isNotEmpty) ...[
                  Text(host.description!),
                  const SizedBox(height: AppSpacing.md),
                ],
                _InfoLine(label: 'Category', value: host.category),
                _InfoLine(label: 'LAN IP', value: host.lanIp ?? 'N/A'),
                _InfoLine(
                  label: 'Tailscale IP',
                  value: host.tailscaleIp ?? 'N/A',
                ),
                _InfoLine(
                  label: 'Hostname',
                  value: host.tailscaleHostname ?? 'N/A',
                ),
                _InfoLine(
                  label: 'Monitoring API',
                  value: host.monitoringApiUrl ?? 'N/A',
                ),
                _InfoLine(
                  label: 'Control API',
                  value: host.controlApiUrl ?? 'N/A',
                ),
                _InfoLine(
                  label: 'Last Checked',
                  value: _formatTime(host.lastChecked),
                ),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    for (final capability in host.capabilities)
                      HostCapabilityChip(capability: capability),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    OutlinedButton(
                      onPressed: () => context.go('/overview'),
                      child: const Text('Overview'),
                    ),
                    OutlinedButton(
                      onPressed: () => context.go('/history'),
                      child: const Text('History'),
                    ),
                    OutlinedButton(
                      onPressed: host.services.isEmpty
                          ? null
                          : () => context.go('/services?hostId=${host.id}'),
                      child: const Text('Services'),
                    ),
                    OutlinedButton(
                      onPressed: () => context.go('/terminal'),
                      child: const Text('Terminal'),
                    ),
                    OutlinedButton(
                      onPressed: () => context.go('/files'),
                      child: const Text('Files'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          SectionCard(
            title: 'Probes',
            child: Column(
              children: [
                for (final probe in host.probes) ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      probe.reachable ? Icons.check_circle : Icons.cancel,
                    ),
                    title: Text(probe.label),
                    subtitle: Text(probe.summary),
                    trailing: probe.port == null ? null : Text('${probe.port}'),
                  ),
                  if (probe != host.probes.last)
                    const Divider(height: AppSpacing.lg),
                ],
              ],
            ),
          ),
        ],
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: EmptyState(
            icon: Icons.dns,
            title: 'Managed host unavailable',
            message: _describeError(error),
            action: FilledButton(
              onPressed: () => ref.invalidate(managedHostProvider(hostId)),
              child: const Text('Retry'),
            ),
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime? value) {
    if (value == null) {
      return 'N/A';
    }
    return DateFormat.yMd().add_Hm().format(value.toLocal());
  }

  String _describeError(Object error) {
    if (error is AppException) {
      return error.message;
    }
    return error.toString();
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
