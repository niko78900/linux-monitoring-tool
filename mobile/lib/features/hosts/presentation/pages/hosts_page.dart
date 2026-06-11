import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/section_card.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../../core/widgets/status_tone.dart';
import '../../domain/models/host_models.dart';
import '../providers/host_providers.dart';

class HostsPage extends ConsumerWidget {
  const HostsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(managedHostsProvider);

    return dashboard.when(
      data: (snapshot) => _HostsView(snapshot: snapshot),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: EmptyState(
            icon: Icons.dns,
            title: 'Managed hosts unavailable',
            message: _describeError(error),
            action: FilledButton.icon(
              onPressed: () => ref.invalidate(managedHostsProvider),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ),
        ),
      ),
    );
  }

  String _describeError(Object error) {
    if (error is AppException) {
      return error.message;
    }
    return error.toString();
  }
}

class _HostsView extends ConsumerWidget {
  const _HostsView({required this.snapshot});

  final ManagedHostsDashboard snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (snapshot.hosts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: EmptyState(
            icon: Icons.dns,
            title: 'No managed hosts configured',
            message: 'Add enabled hosts in the control-agent managed-host YAML.',
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Hosts',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            IconButton(
              tooltip: 'Refresh hosts',
              onPressed: () => ref.invalidate(managedHostsProvider),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Managed hosts are explicit inventory entries, not a network scan.',
        ),
        const SizedBox(height: AppSpacing.lg),
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            for (final host in snapshot.hosts)
              SizedBox(
                width: 380,
                child: ManagedHostCard(host: host),
              ),
          ],
        ),
      ],
    );
  }
}

class ManagedHostCard extends StatelessWidget {
  const ManagedHostCard({super.key, required this.host});

  final ManagedHost host;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: host.displayName,
      trailing: HostStatusBadge(host: host),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (host.description != null && host.description!.trim().isNotEmpty) ...[
            Text(host.description!),
            const SizedBox(height: AppSpacing.md),
          ],
          _InfoLine(label: 'Category', value: host.category),
          _InfoLine(label: 'LAN IP', value: host.lanIp ?? 'N/A'),
          _InfoLine(label: 'Tailscale IP', value: host.tailscaleIp ?? 'N/A'),
          _InfoLine(
            label: 'Latency',
            value: host.latencyMs == null
                ? 'N/A'
                : '${host.latencyMs!.toStringAsFixed(1)} ms',
          ),
          _InfoLine(
            label: 'Last Seen',
            value: _formatTime(host.lastSeen ?? host.lastChecked),
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
                onPressed: () => context.go('/hosts/${host.id}'),
                child: const Text('Details'),
              ),
              TextButton(
                onPressed: () => context.go('/overview'),
                child: const Text('Overview'),
              ),
              TextButton(
                onPressed: () => context.go('/history'),
                child: const Text('History'),
              ),
              TextButton(
                onPressed: host.services.isEmpty ? null : null,
                child: const Text('Services'),
              ),
              TextButton(
                onPressed: () => context.go('/terminal'),
                child: const Text('Terminal'),
              ),
              TextButton(
                onPressed: () => context.go('/files'),
                child: const Text('Files'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime? value) {
    if (value == null) {
      return 'N/A';
    }
    return DateFormat.yMd().add_Hm().format(value.toLocal());
  }
}

class HostCapabilityChip extends StatelessWidget {
  const HostCapabilityChip({super.key, required this.capability});

  final String capability;

  @override
  Widget build(BuildContext context) {
    return Chip(label: Text(capability.replaceAll('_', ' ')));
  }
}

class HostStatusBadge extends StatelessWidget {
  const HostStatusBadge({super.key, required this.host});

  final ManagedHost host;

  @override
  Widget build(BuildContext context) {
    return StatusBadge(
      label: host.online ? 'Online' : 'Unreachable',
      tone: host.online ? StatusTone.healthy : StatusTone.offline,
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: [
          SizedBox(
            width: 96,
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
