import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_spacing.dart';

class PhoneMorePage extends StatelessWidget {
  const PhoneMorePage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: const [
        _MoreDestination(
          icon: Icons.developer_board,
          title: 'GPU',
          subtitle: 'Utilization, temperature, memory, and hardware details',
          path: '/gpu',
        ),
        _MoreDestination(
          icon: Icons.query_stats,
          title: 'History',
          subtitle: 'Historical performance, storage, disk, and RAID metrics',
          path: '/history',
        ),
        _MoreDestination(
          icon: Icons.power_settings_new,
          title: 'Wake Main PC',
          subtitle: 'Authenticated, confirmed Wake-on-LAN action',
          path: '/wake',
        ),
        _MoreDestination(
          icon: Icons.settings,
          title: 'Settings',
          subtitle: 'Connections, alerts, widgets, and Wake security',
          path: '/settings',
        ),
      ],
    );
  }
}

class _MoreDestination extends StatelessWidget {
  const _MoreDestination({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.path,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String path;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.go(path),
      ),
    );
  }
}
