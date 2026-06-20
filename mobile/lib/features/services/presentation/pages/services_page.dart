import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
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
import '../service_dashboard_filters.dart';
import '../providers/service_providers.dart';

class ServicesPage extends ConsumerStatefulWidget {
  const ServicesPage({super.key, this.hostId});

  final String? hostId;

  @override
  ConsumerState<ServicesPage> createState() => _ServicesPageState();
}

class _ServicesPageState extends ConsumerState<ServicesPage> {
  final Set<String> _pendingActions = <String>{};
  final TextEditingController _searchController = TextEditingController();
  String? _message;
  String _searchQuery = '';
  String _categoryFilter = 'all';
  String _runtimeFilter = 'all';
  String _healthFilter = 'all';
  ServiceSortMode _sortMode = ServiceSortMode.unhealthyFirst;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final servicesState = ref.watch(serviceListProvider);

    return servicesState.when(
      data: (services) {
        final hostServices = widget.hostId == null
            ? services
            : services
                  .where((service) => service.hostId == widget.hostId)
                  .toList();
        if (hostServices.isEmpty) {
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
        final visible = filterAndSortServices(
          services: hostServices,
          searchQuery: _searchQuery,
          category: _categoryFilter,
          runtime: _runtimeFilter,
          health: _healthFilter,
          sortMode: _sortMode,
        );
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
            _ServiceDashboardControls(
              searchController: _searchController,
              searchQuery: _searchQuery,
              categories: serviceCategories(hostServices),
              categoryFilter: _categoryFilter,
              runtimeFilter: _runtimeFilter,
              healthFilter: _healthFilter,
              sortMode: _sortMode,
              totalCount: hostServices.length,
              visibleCount: visible.length,
              onSearchChanged: (value) => setState(() {
                _searchQuery = value;
              }),
              onCategoryChanged: (value) => setState(() {
                _categoryFilter = value;
              }),
              onRuntimeChanged: (value) => setState(() {
                _runtimeFilter = value;
              }),
              onHealthChanged: (value) => setState(() {
                _healthFilter = value;
              }),
              onSortChanged: (value) => setState(() {
                _sortMode = value;
              }),
              onClear: _clearFilters,
            ),
            const SizedBox(height: AppSpacing.lg),
            if (visible.isEmpty)
              EmptyState(
                icon: Icons.filter_alt_off,
                title: 'No matching services',
                message: 'Adjust the search or filters to show services.',
                action: OutlinedButton.icon(
                  onPressed: _clearFilters,
                  icon: const Icon(Icons.clear_all),
                  label: const Text('Clear filters'),
                ),
              )
            else
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
                        onDetails: () =>
                            context.go('/services/${service.serviceId}'),
                        onOpenUrl: service.url == null
                            ? null
                            : () => _openUrl(service.url!),
                        onCopyUrl: service.url == null
                            ? null
                            : () => _copy(service.url!, 'Service URL copied.'),
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

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _categoryFilter = 'all';
      _runtimeFilter = 'all';
      _healthFilter = 'all';
      _sortMode = ServiceSortMode.unhealthyFirst;
    });
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
}

class _ServiceDashboardControls extends StatelessWidget {
  const _ServiceDashboardControls({
    required this.searchController,
    required this.searchQuery,
    required this.categories,
    required this.categoryFilter,
    required this.runtimeFilter,
    required this.healthFilter,
    required this.sortMode,
    required this.totalCount,
    required this.visibleCount,
    required this.onSearchChanged,
    required this.onCategoryChanged,
    required this.onRuntimeChanged,
    required this.onHealthChanged,
    required this.onSortChanged,
    required this.onClear,
  });

  final TextEditingController searchController;
  final String searchQuery;
  final List<String> categories;
  final String categoryFilter;
  final String runtimeFilter;
  final String healthFilter;
  final ServiceSortMode sortMode;
  final int totalCount;
  final int visibleCount;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onCategoryChanged;
  final ValueChanged<String> onRuntimeChanged;
  final ValueChanged<String> onHealthChanged;
  final ValueChanged<ServiceSortMode> onSortChanged;
  final VoidCallback onClear;

  bool get _hasFilters =>
      searchQuery.trim().isNotEmpty ||
      categoryFilter != 'all' ||
      runtimeFilter != 'all' ||
      healthFilter != 'all' ||
      sortMode != ServiceSortMode.unhealthyFirst;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Service dashboard',
      trailing: Text('$visibleCount of $totalCount visible'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 320,
                child: TextField(
                  controller: searchController,
                  onChanged: onSearchChanged,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    labelText: 'Search services',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              DropdownButton<ServiceSortMode>(
                value: sortMode,
                onChanged: (value) {
                  if (value != null) {
                    onSortChanged(value);
                  }
                },
                items: [
                  for (final mode in ServiceSortMode.values)
                    DropdownMenuItem(value: mode, child: Text(mode.label)),
                ],
              ),
              OutlinedButton.icon(
                onPressed: _hasFilters ? onClear : null,
                icon: const Icon(Icons.clear_all),
                label: const Text('Clear'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _FilterChipGroup(
            label: 'Category',
            selected: categoryFilter,
            options: [
              const _FilterOption('all', 'All'),
              for (final category in categories)
                _FilterOption(category.toLowerCase(), category),
            ],
            onSelected: onCategoryChanged,
          ),
          const SizedBox(height: AppSpacing.sm),
          _FilterChipGroup(
            label: 'Runtime',
            selected: runtimeFilter,
            options: const [
              _FilterOption('all', 'All'),
              _FilterOption('running', 'Running'),
              _FilterOption('stopped', 'Stopped'),
              _FilterOption('unknown', 'Unknown'),
            ],
            onSelected: onRuntimeChanged,
          ),
          const SizedBox(height: AppSpacing.sm),
          _FilterChipGroup(
            label: 'Health',
            selected: healthFilter,
            options: const [
              _FilterOption('all', 'All'),
              _FilterOption('healthy', 'Healthy'),
              _FilterOption('unhealthy', 'Unhealthy'),
              _FilterOption('unknown', 'Unknown'),
            ],
            onSelected: onHealthChanged,
          ),
        ],
      ),
    );
  }
}

class _FilterChipGroup extends StatelessWidget {
  const _FilterChipGroup({
    required this.label,
    required this.selected,
    required this.options,
    required this.onSelected,
  });

  final String label;
  final String selected;
  final List<_FilterOption> options;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        for (final option in options)
          FilterChip(
            label: Text(option.label),
            selected: option.value == selected,
            onSelected: (_) => onSelected(option.value),
            showCheckmark: false,
          ),
      ],
    );
  }
}

class _FilterOption {
  const _FilterOption(this.value, this.label);

  final String value;
  final String label;
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
        Text(
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

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({
    required this.service,
    required this.pending,
    required this.onRefresh,
    required this.onAction,
    required this.onDetails,
    required this.onOpenUrl,
    required this.onCopyUrl,
  });

  final ManagedService service;
  final bool pending;
  final VoidCallback onRefresh;
  final ValueChanged<String> onAction;
  final VoidCallback onDetails;
  final VoidCallback? onOpenUrl;
  final VoidCallback? onCopyUrl;

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
              StatusBadge(label: service.category, tone: StatusTone.neutral),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _InfoLine(
            label: service.runtimeAdapter == 'docker' ? 'Container' : 'Unit',
            value: service.runtimeTarget,
          ),
          _InfoLine(label: 'URL', value: service.url ?? 'Not configured'),
          _InfoLine(
            label: 'Ports',
            value: service.ports.isEmpty
                ? 'Not configured'
                : service.ports.join(', '),
          ),
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
              OutlinedButton.icon(
                onPressed: onDetails,
                icon: const Icon(Icons.dashboard_customize),
                label: const Text('Details'),
              ),
              OutlinedButton.icon(
                onPressed: onOpenUrl,
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open'),
              ),
              IconButton(
                tooltip: 'Copy service URL',
                onPressed: onCopyUrl,
                icon: const Icon(Icons.copy),
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
