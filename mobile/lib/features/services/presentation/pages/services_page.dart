import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/section_card.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../../core/widgets/status_tone.dart';
import '../../data/service_repository.dart';
import '../../domain/models/service_models.dart';
import '../providers/service_providers.dart';

class ServicesPage extends ConsumerStatefulWidget {
  const ServicesPage({super.key, this.hostId});

  final String? hostId;

  @override
  ConsumerState<ServicesPage> createState() => _ServicesPageState();
}

class _ServicesPageState extends ConsumerState<ServicesPage> {
  final Set<String> _pendingActions = <String>{};
  String? _message;

  @override
  Widget build(BuildContext context) {
    final servicesState = ref.watch(serviceListProvider);

    return servicesState.when(
      data: (services) {
        final visible = widget.hostId == null
            ? services
            : services
                  .where((service) => service.hostId == widget.hostId)
                  .toList();
        if (visible.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: EmptyState(
              icon: Icons.miscellaneous_services,
              title: 'No services configured',
              message:
                  'Add allowlisted services in the control-agent registry.',
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
                    'Services',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh services',
                  onPressed: () => ref.invalidate(serviceListProvider),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            if (_message != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_message!),
            ],
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
              children: [
                for (final service in visible)
                  SizedBox(
                    width: 420,
                    child: _ServiceCard(
                      service: service,
                      pending: _pendingActions.contains(service.serviceId),
                      onRefresh: () => ref.invalidate(serviceListProvider),
                      onAction: (action) => _confirmAction(service, action),
                    ),
                  ),
              ],
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: EmptyState(
            icon: Icons.miscellaneous_services,
            title: 'Service controls unavailable',
            message: _describeError(error),
            action: FilledButton.icon(
              onPressed: () => ref.invalidate(serviceListProvider),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmAction(ManagedService service, String action) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('${_titleCase(action)} ${service.displayName}?'),
          content: Text(
            'Send the allowlisted $action action for ${service.displayName}.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(_titleCase(action)),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }
    await _runAction(service, action);
  }

  Future<void> _runAction(ManagedService service, String action) async {
    setState(() {
      _pendingActions.add(service.serviceId);
      _message = null;
    });

    try {
      final result = await ref
          .read(serviceRepositoryProvider)
          .sendAction(serviceId: service.serviceId, action: action);
      if (!mounted) {
        return;
      }
      setState(() {
        _message = '${service.displayName}: ${result.status}';
      });
      ref.invalidate(serviceListProvider);
      await Future<void>.delayed(const Duration(seconds: 1));
      if (mounted) {
        ref.invalidate(serviceListProvider);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _message = _describeError(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _pendingActions.remove(service.serviceId);
        });
      }
    }
  }

  String _describeError(Object error) {
    if (error is AppException) {
      return error.message;
    }
    return error.toString();
  }

  String _titleCase(String value) {
    if (value.isEmpty) {
      return value;
    }
    return '${value[0].toUpperCase()}${value.substring(1)}';
  }
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({
    required this.service,
    required this.pending,
    required this.onRefresh,
    required this.onAction,
  });

  final ManagedService service;
  final bool pending;
  final VoidCallback onRefresh;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: service.displayName,
      trailing: StatusBadge(
        label: _runtimeLabel(service.runtimeState),
        tone: _runtimeTone(service.runtimeState),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              StatusBadge(
                label: 'HTTP ${service.healthProbeState}',
                tone: _healthTone(service.healthProbeState),
              ),
              StatusBadge(
                label: service.runtimeAdapter,
                tone: StatusTone.neutral,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _InfoLine(
            label: 'Last checked',
            value: _formatTime(service.lastChecked),
          ),
          _InfoLine(
            label: 'Last action',
            value: service.lastAction == null
                ? 'None'
                : '${service.lastAction!.action} ${service.lastAction!.status}',
          ),
          if (service.lastAction?.detail case final detail?)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(detail),
            ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              IconButton(
                tooltip: 'Refresh',
                onPressed: pending ? null : onRefresh,
                icon: const Icon(Icons.refresh),
              ),
              FilledButton.icon(
                onPressed: pending || !service.allows('start')
                    ? null
                    : () => onAction('start'),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start'),
              ),
              OutlinedButton.icon(
                onPressed: pending || !service.allows('restart')
                    ? null
                    : () => onAction('restart'),
                icon: const Icon(Icons.restart_alt),
                label: const Text('Restart'),
              ),
              OutlinedButton.icon(
                onPressed: pending || !service.allows('stop')
                    ? null
                    : () => onAction('stop'),
                icon: const Icon(Icons.stop),
                label: Text(pending ? 'Working...' : 'Stop'),
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

  String _runtimeLabel(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'running' || normalized == 'active') {
      return 'Running';
    }
    if (normalized == 'stopped' || normalized == 'inactive') {
      return 'Stopped';
    }
    return normalized.isEmpty ? 'Unknown' : normalized;
  }

  StatusTone _runtimeTone(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'running' || normalized == 'active') {
      return StatusTone.healthy;
    }
    if (normalized == 'stopped' || normalized == 'inactive') {
      return StatusTone.offline;
    }
    return StatusTone.warning;
  }

  StatusTone _healthTone(String value) {
    return switch (value) {
      'healthy' => StatusTone.healthy,
      'unreachable' || 'timeout' => StatusTone.critical,
      _ => StatusTone.warning,
    };
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
