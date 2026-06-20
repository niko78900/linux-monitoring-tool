import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/section_card.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../../core/widgets/status_tone.dart';
import '../../data/service_repository.dart';
import '../../domain/models/service_models.dart';
import '../providers/service_providers.dart';

class ServiceDetailPage extends ConsumerStatefulWidget {
  const ServiceDetailPage({super.key, required this.serviceId});

  final String serviceId;

  @override
  ConsumerState<ServiceDetailPage> createState() => _ServiceDetailPageState();
}

class _ServiceDetailPageState extends ConsumerState<ServiceDetailPage> {
  final Set<String> _pendingActions = <String>{};
  String? _message;

  @override
  Widget build(BuildContext context) {
    final serviceState = ref.watch(serviceDetailsProvider(widget.serviceId));

    return serviceState.when(
      data: (service) => ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Back to services',
                onPressed: () => context.go('/services'),
                icon: const Icon(Icons.arrow_back),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  service.displayName,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              StatusBadge(
                label: _runtimeLabel(service.runtimeState),
                tone: _runtimeTone(service.runtimeState),
              ),
              IconButton(
                tooltip: 'Refresh service',
                onPressed: () =>
                    ref.invalidate(serviceDetailsProvider(widget.serviceId)),
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
              SizedBox(
                width: 460,
                child: SectionCard(
                  title: 'Runtime',
                  trailing: StatusBadge(
                    label: _runtimeLabel(service.runtimeState),
                    tone: _runtimeTone(service.runtimeState),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (service.description != null &&
                          service.description!.trim().isNotEmpty) ...[
                        Text(service.description!),
                        const SizedBox(height: AppSpacing.md),
                      ],
                      _InfoLine(label: 'Category', value: service.category),
                      _InfoLine(label: 'Host', value: service.hostId),
                      _InfoLine(
                        label: service.runtimeAdapter == 'docker'
                            ? 'Container'
                            : 'Unit',
                        value: service.runtimeTarget,
                        selectable: true,
                      ),
                      _InfoLine(
                        label: 'Adapter',
                        value: service.runtimeAdapter,
                      ),
                      if (service.image != null)
                        _InfoLine(
                          label: 'Image',
                          value: service.image!,
                          selectable: true,
                        ),
                      const SizedBox(height: AppSpacing.md),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () =>
                                _copy(service.serviceId, 'Service ID copied.'),
                            icon: const Icon(Icons.copy),
                            label: const Text('Copy ID'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () =>
                                _copy(service.runtimeTarget, 'Target copied.'),
                            icon: const Icon(Icons.copy_all),
                            label: const Text('Copy target'),
                          ),
                          OutlinedButton.icon(
                            onPressed: service.image == null
                                ? null
                                : () => _copy(service.image!, 'Image copied.'),
                            icon: const Icon(Icons.inventory_2_outlined),
                            label: const Text('Copy image'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(
                width: 420,
                child: SectionCard(
                  title: 'Health',
                  trailing: StatusBadge(
                    label: service.healthProbeState,
                    tone: _healthTone(service.healthProbeState),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _InfoLine(
                        label: 'State',
                        value: service.healthProbeState,
                      ),
                      _InfoLine(
                        label: 'Last checked',
                        value: _formatTime(service.lastChecked),
                      ),
                      if (service.url == null)
                        const Text('No service URL configured for probing.')
                      else
                        Text('Probe target: ${service.url}'),
                    ],
                  ),
                ),
              ),
              SizedBox(
                width: 420,
                child: SectionCard(
                  title: 'Ports & URL',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _InfoLine(
                        label: 'URL',
                        value: service.url ?? 'Not configured',
                        selectable: service.url != null,
                      ),
                      _InfoLine(
                        label: 'Ports',
                        value: service.ports.isEmpty
                            ? 'Not configured'
                            : service.ports.join(', '),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: [
                          OutlinedButton.icon(
                            onPressed: service.url == null
                                ? null
                                : () => _openUrl(service.url!),
                            icon: const Icon(Icons.open_in_new),
                            label: const Text('Open'),
                          ),
                          OutlinedButton.icon(
                            onPressed: service.url == null
                                ? null
                                : () => _copy(service.url!, 'URL copied.'),
                            icon: const Icon(Icons.copy),
                            label: const Text('Copy URL'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(
                width: 420,
                child: SectionCard(
                  title: 'Actions',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Actions are executed by the control agent only when they are allowlisted for this service.',
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: [
                          FilledButton.icon(
                            onPressed: _canRun(service, 'start')
                                ? () => _confirmAction(service, 'start')
                                : null,
                            icon: const Icon(Icons.play_arrow),
                            label: const Text('Start'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _canRun(service, 'restart')
                                ? () => _confirmAction(service, 'restart')
                                : null,
                            icon: const Icon(Icons.restart_alt),
                            label: const Text('Restart'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _canRun(service, 'stop')
                                ? () => _confirmAction(service, 'stop')
                                : null,
                            icon: const Icon(Icons.stop),
                            label: const Text('Stop'),
                          ),
                          OutlinedButton.icon(
                            onPressed: service.url == null
                                ? null
                                : () => _openUrl(service.url!),
                            icon: const Icon(Icons.open_in_new),
                            label: const Text('Open URL'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(
                width: 420,
                child: SectionCard(
                  title: 'Last Action',
                  child: service.lastAction == null
                      ? const Text('No recent service action.')
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _InfoLine(
                              label: 'Action',
                              value: service.lastAction!.action,
                            ),
                            _InfoLine(
                              label: 'Status',
                              value: service.lastAction!.status,
                            ),
                            _InfoLine(
                              label: 'Requested',
                              value: _formatTime(
                                service.lastAction!.requestedAt,
                              ),
                            ),
                            _InfoLine(
                              label: 'Detail',
                              value: service.lastAction!.detail ?? 'No detail',
                            ),
                          ],
                        ),
                ),
              ),
              SizedBox(
                width: 420,
                child: SectionCard(
                  title: 'Metadata',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _InfoLine(
                        label: 'Service ID',
                        value: service.serviceId,
                        selectable: true,
                      ),
                      _InfoLine(label: 'Host', value: service.hostId),
                      _InfoLine(label: 'Category', value: service.category),
                      _InfoLine(
                        label: 'Actions',
                        value: service.allowedActions.isEmpty
                            ? 'None'
                            : service.allowedActions.join(', '),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: EmptyState(
            icon: Icons.miscellaneous_services,
            title: 'Service unavailable',
            message: _describeError(error),
            action: FilledButton.icon(
              onPressed: () =>
                  ref.invalidate(serviceDetailsProvider(widget.serviceId)),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ),
        ),
      ),
    );
  }

  bool _canRun(ManagedService service, String action) {
    return !_pendingActions.contains(action) && service.allows(action);
  }

  Future<void> _confirmAction(ManagedService service, String action) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${_titleCase(action)} ${service.displayName}?'),
        content: _ActionConfirmationDetails(service: service, action: action),
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
      ),
    );
    if (confirmed == true) {
      await _runAction(service, action);
    }
  }

  Future<void> _runAction(ManagedService service, String action) async {
    setState(() {
      _pendingActions.add(action);
      _message = null;
    });
    try {
      final result = await ref
          .read(serviceRepositoryProvider)
          .sendAction(serviceId: service.serviceId, action: action);
      if (!mounted) {
        return;
      }
      setState(() => _message = '${service.displayName}: ${result.status}');
      ref.invalidate(serviceListProvider);
      ref.invalidate(serviceDetailsProvider(service.serviceId));
      await Future<void>.delayed(const Duration(seconds: 1));
      if (mounted) {
        ref.invalidate(serviceListProvider);
        ref.invalidate(serviceDetailsProvider(service.serviceId));
      }
    } catch (error) {
      if (mounted) {
        setState(() => _message = _describeError(error));
      }
    } finally {
      if (mounted) {
        setState(() => _pendingActions.remove(action));
      }
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      _showSnackBar('Service URL is invalid.');
      return;
    }
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched) {
      _showSnackBar('No app could open this URL.');
    }
  }

  Future<void> _copy(String value, String message) async {
    await Clipboard.setData(ClipboardData(text: value));
    _showSnackBar(message);
  }

  void _showSnackBar(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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

  String _titleCase(String value) {
    if (value.isEmpty) {
      return value;
    }
    return '${value[0].toUpperCase()}${value.substring(1)}';
  }
}

class _ActionConfirmationDetails extends StatelessWidget {
  const _ActionConfirmationDetails({
    required this.service,
    required this.action,
  });

  final ManagedService service;
  final String action;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'This sends a server-side allowlisted action. No arbitrary command will be executed.',
        ),
        const SizedBox(height: AppSpacing.md),
        _InfoLine(label: 'Service', value: service.displayName),
        _InfoLine(label: 'Action', value: action),
        _InfoLine(label: 'Host', value: service.hostId),
        _InfoLine(label: 'Target', value: service.runtimeTarget),
      ],
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({
    required this.label,
    required this.value,
    this.selectable = false,
  });

  final String label;
  final String value;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final valueWidget = selectable
        ? SelectableText(value)
        : Text(value, overflow: TextOverflow.ellipsis, maxLines: 2);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: [
          SizedBox(
            width: 108,
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: valueWidget),
        ],
      ),
    );
  }
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
    'unconfigured' => StatusTone.neutral,
    _ => StatusTone.warning,
  };
}
