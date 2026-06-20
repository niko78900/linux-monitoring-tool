import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/section_card.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../../core/widgets/status_tone.dart';
import '../../data/control_repository.dart';
import '../../domain/models/device_models.dart';
import '../providers/control_providers.dart';

class DeviceDetailPage extends ConsumerStatefulWidget {
  const DeviceDetailPage({super.key, required this.deviceId});

  final String deviceId;

  @override
  ConsumerState<DeviceDetailPage> createState() => _DeviceDetailPageState();
}

class _DeviceDetailPageState extends ConsumerState<DeviceDetailPage> {
  bool _waking = false;
  String? _statusMessage;

  @override
  Widget build(BuildContext context) {
    final deviceState = ref.watch(knownDeviceProvider(widget.deviceId));
    return deviceState.when(
      data: (device) => ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              IconButton(
                tooltip: 'Back',
                onPressed: () => context.go('/devices'),
                icon: const Icon(Icons.arrow_back),
              ),
              Text(
                device.name,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              StatusBadge(
                label: device.online ? 'Online' : 'Offline',
                tone: device.online ? StatusTone.healthy : StatusTone.offline,
              ),
              if (_statusMessage != null) Text(_statusMessage!),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          SectionCard(
            title: 'Device',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InfoLine(label: 'Category', value: device.category),
                _InfoLine(label: 'LAN IP', value: device.lanIp ?? 'N/A'),
                _InfoLine(
                  label: 'Tailscale IP',
                  value: device.tailscaleIp ?? 'N/A',
                ),
                if (device.tailscaleHostName != null)
                  _InfoLine(label: 'TS Host', value: device.tailscaleHostName!),
                if (device.tailscaleDnsName != null)
                  _InfoLine(label: 'TS DNS', value: device.tailscaleDnsName!),
                if (device.tailscaleOs != null)
                  _InfoLine(label: 'TS OS', value: device.tailscaleOs!),
                if (device.tailscaleOnline != null)
                  _InfoLine(
                    label: 'TS Status',
                    value: device.tailscaleOnline! ? 'Online' : 'Offline',
                  ),
                _InfoLine(
                  label: 'Latency',
                  value: device.latencyMs == null
                      ? 'N/A'
                      : '${device.latencyMs!.toStringAsFixed(1)} ms',
                ),
                _InfoLine(
                  label: 'Last Checked',
                  value: _formatTime(device.lastChecked),
                ),
                _InfoLine(
                  label: 'Last Seen',
                  value: _formatTime(
                    device.lastSeen ?? device.tailscaleLastSeen,
                  ),
                ),
                if (device.notes != null &&
                    device.notes!.trim().isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(device.notes!),
                ],
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _refreshStatus,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Refresh status'),
                    ),
                    if (device.preferredIp != null)
                      OutlinedButton.icon(
                        onPressed: () => _copyIp(device.preferredIp!),
                        icon: const Icon(Icons.copy_all),
                        label: const Text('Copy IP address'),
                      ),
                    if (_canOpenTerminal(device))
                      OutlinedButton.icon(
                        onPressed: () => context.go('/terminal'),
                        icon: const Icon(Icons.terminal),
                        label: const Text('Open terminal'),
                      ),
                    if (device.wolEnabled)
                      FilledButton.icon(
                        onPressed: _waking ? null : () => _wakeDevice(device),
                        icon: const Icon(Icons.power_settings_new),
                        label: Text(_waking ? 'Sending...' : 'Wake Main PC'),
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
                for (final probe in device.probes) ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      probe.reachable ? Icons.check_circle : Icons.cancel,
                    ),
                    title: Text(probe.label),
                    subtitle: Text(probe.summary),
                    trailing: probe.port == null ? null : Text('${probe.port}'),
                  ),
                  if (probe != device.probes.last)
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
            icon: Icons.device_unknown,
            title: 'Device unavailable',
            message: _describeError(error),
            action: FilledButton(
              onPressed: _refreshStatus,
              child: const Text('Retry'),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _wakeDevice(KnownDevice device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Wake ${device.name}?'),
          content: const Text(
            'Send the allowlisted Wake-on-LAN action and poll for status updates.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Wake'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }

    setState(() {
      _waking = true;
      _statusMessage = null;
    });

    try {
      await ref.read(controlRepositoryProvider).wakeMainPc();
      if (!mounted) {
        return;
      }
      setState(() => _statusMessage = 'Wake accepted. Polling for status.');
      await _pollAfterWake();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _statusMessage = _describeError(error));
    } finally {
      if (mounted) {
        setState(() => _waking = false);
      }
    }
  }

  Future<void> _pollAfterWake() async {
    for (var attempt = 0; attempt < 6; attempt += 1) {
      ref.invalidate(devicesDashboardProvider);
      try {
        final device = await ref.read(
          knownDeviceProvider(widget.deviceId).future,
        );
        if (device.online) {
          if (mounted) {
            setState(() => _statusMessage = '${device.name} is online.');
          }
          return;
        }
      } catch (_) {
        // Keep polling until the attempts are exhausted.
      }
      await Future<void>.delayed(const Duration(seconds: 5));
    }
    if (mounted) {
      setState(
        () => _statusMessage =
            'Wake sent. Device is still offline from this view.',
      );
    }
  }

  void _refreshStatus() {
    ref.invalidate(devicesDashboardProvider);
    ref.invalidate(knownDeviceProvider(widget.deviceId));
  }

  Future<void> _copyIp(String ipAddress) async {
    await Clipboard.setData(ClipboardData(text: ipAddress));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('IP address copied')));
  }

  bool _canOpenTerminal(KnownDevice device) {
    return device.category == 'server';
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
