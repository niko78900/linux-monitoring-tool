import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../../core/widgets/status_tone.dart';
import '../../presentation/providers/monitoring_controller.dart';

class HealthStrip extends StatelessWidget {
  const HealthStrip({super.key, required this.state});

  final MonitoringState state;

  @override
  Widget build(BuildContext context) {
    final system = state.system.data;
    final gpu = state.gpu.data;
    final docker = state.docker.data;
    final raidTone = _raidTone(system);
    final diskTone = _diskTone(system);

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        StatusBadge(
          label: state.serverReachable
              ? 'Server reachable'
              : 'Server unreachable',
          tone: state.serverReachable ? StatusTone.healthy : StatusTone.offline,
          onTap: () => context.go('/hardware'),
        ),
        StatusBadge(
          label: 'RAID ${_raidLabel(system)}',
          tone: raidTone,
          onTap: () => context.go('/storage'),
        ),
        StatusBadge(
          label: 'Disks ${_diskLabel(system)}',
          tone: diskTone,
          onTap: () => context.go('/storage'),
        ),
        StatusBadge(
          label: gpu?.available == true ? 'GPU available' : 'GPU unavailable',
          tone: gpu?.available == true
              ? StatusTone.healthy
              : StatusTone.unknown,
          onTap: () => context.go('/gpu'),
        ),
        StatusBadge(
          label: docker?.dockerAvailable == true
              ? 'Docker available'
              : 'Docker unavailable',
          tone: docker?.dockerAvailable == true
              ? StatusTone.healthy
              : StatusTone.unknown,
          onTap: () => context.go('/services'),
        ),
        StatusBadge(
          label: 'Control agent optional',
          tone: StatusTone.neutral,
          onTap: () => context.go('/actions'),
        ),
      ],
    );
  }

  String _raidLabel(dynamic system) {
    final arrays = system?.raidArrays as List<dynamic>?;
    if (arrays == null || arrays.isEmpty) {
      return 'none';
    }
    final critical = arrays
        .where((item) => item.health.status == 'critical')
        .length;
    final warning = arrays
        .where((item) => item.health.status == 'warning')
        .length;
    if (critical > 0) {
      return 'critical';
    }
    if (warning > 0) {
      return 'warning';
    }
    return 'healthy';
  }

  StatusTone _raidTone(dynamic system) {
    return switch (_raidLabel(system)) {
      'healthy' => StatusTone.healthy,
      'warning' => StatusTone.warning,
      'critical' => StatusTone.critical,
      _ => StatusTone.neutral,
    };
  }

  String _diskLabel(dynamic system) {
    final disks = system?.physicalDisks as List<dynamic>?;
    if (disks == null || disks.isEmpty) {
      return 'unknown';
    }
    final healthy = disks
        .where((item) => item.health.status == 'healthy')
        .length;
    return '$healthy/${disks.length} healthy';
  }

  StatusTone _diskTone(dynamic system) {
    final disks = system?.physicalDisks as List<dynamic>?;
    if (disks == null || disks.isEmpty) {
      return StatusTone.unknown;
    }
    if (disks.any((item) => item.health.status == 'critical')) {
      return StatusTone.critical;
    }
    if (disks.any((item) => item.health.status == 'warning')) {
      return StatusTone.warning;
    }
    return StatusTone.healthy;
  }
}
