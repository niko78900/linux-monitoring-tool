import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/display_name_format.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/section_card.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../../core/widgets/status_tone.dart';
import '../../domain/models/device_models.dart';
import '../providers/control_providers.dart';

class DevicesPage extends ConsumerWidget {
  const DevicesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(devicesDashboardProvider);

    return dashboard.when(
      data: (snapshot) => _DevicesView(snapshot: snapshot),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: EmptyState(
            icon: Icons.devices_other,
            title: 'Known devices unavailable',
            message: _describeError(error),
            action: FilledButton.icon(
              onPressed: () => ref.invalidate(devicesDashboardProvider),
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

class _DevicesView extends ConsumerWidget {
  const _DevicesView({required this.snapshot});

  final DevicesDashboard snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Known Devices',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            IconButton(
              tooltip: 'Refresh devices',
              onPressed: () => ref.invalidate(devicesDashboardProvider),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Known devices and Tailscale peers are shown here. LAN neighbor scans are intentionally omitted.',
        ),
        const SizedBox(height: AppSpacing.lg),
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            for (final device in snapshot.devices)
              SizedBox(width: 360, child: _DeviceCard(device: device)),
          ],
        ),
      ],
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.device});

  final KnownDevice device;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: formatDeviceDisplayName(device.name),
      trailing: StatusBadge(
        label: device.online ? 'Online' : 'Offline',
        tone: device.online ? StatusTone.healthy : StatusTone.offline,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_iconForCategory(device.category)),
              const SizedBox(width: AppSpacing.sm),
              Text(device.category),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _InfoLine(label: 'LAN IP', value: device.lanIp ?? 'N/A'),
          _InfoLine(label: 'Tailscale IP', value: device.tailscaleIp ?? 'N/A'),
          _InfoLine(
            label: 'Latency',
            value: device.latencyMs == null
                ? 'N/A'
                : '${device.latencyMs!.toStringAsFixed(1)} ms',
          ),
          _InfoLine(
            label: 'Last Seen',
            value: _formatTime(device.lastSeen ?? device.lastChecked),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            device.probeSummary,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              OutlinedButton(
                onPressed: () => context.go('/devices/${device.id}'),
                child: const Text('Details'),
              ),
              if (device.preferredIp != null)
                TextButton(
                  onPressed: () => Clipboard.setData(
                    ClipboardData(text: device.preferredIp!),
                  ),
                  child: const Text('Copy IP'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  IconData _iconForCategory(String category) {
    return switch (category) {
      'server' => Icons.dns,
      'desktop' => Icons.desktop_windows,
      'laptop' => Icons.laptop,
      'tablet' => Icons.tablet_android,
      'phone' => Icons.smartphone,
      'router' => Icons.router,
      _ => Icons.devices_other,
    };
  }

  String _formatTime(DateTime? value) {
    if (value == null) {
      return 'N/A';
    }
    return DateFormat.yMd().add_Hm().format(value.toLocal());
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
