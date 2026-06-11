import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../config/app_settings.dart';
import '../security/app_lock_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

class AppDestination {
  const AppDestination({
    required this.label,
    required this.path,
    required this.icon,
    this.privileged = false,
    this.primary = true,
  });

  final String label;
  final String path;
  final IconData icon;
  final bool privileged;
  final bool primary;
}

const appDestinations = [
  AppDestination(label: 'Overview', path: '/overview', icon: Icons.dashboard),
  AppDestination(label: 'Hardware', path: '/hardware', icon: Icons.memory),
  AppDestination(label: 'Storage', path: '/storage', icon: Icons.storage),
  AppDestination(label: 'GPU', path: '/gpu', icon: Icons.developer_board),
  AppDestination(label: 'Network', path: '/network', icon: Icons.hub),
  AppDestination(
    label: 'History',
    path: '/history',
    icon: Icons.query_stats,
    primary: false,
  ),
  AppDestination(
    label: 'Devices',
    path: '/devices',
    icon: Icons.devices_other,
    primary: false,
  ),
  AppDestination(
    label: 'Actions',
    path: '/actions',
    icon: Icons.power_settings_new,
    privileged: true,
    primary: false,
  ),
  AppDestination(
    label: 'Terminal',
    path: '/terminal',
    icon: Icons.terminal,
    privileged: true,
  ),
  AppDestination(
    label: 'Files',
    path: '/files',
    icon: Icons.folder,
    privileged: true,
  ),
  AppDestination(
    label: 'Settings',
    path: '/settings',
    icon: Icons.settings,
    primary: false,
  ),
];

class AppScaffold extends ConsumerWidget {
  const AppScaffold({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.sizeOf(context).width;
    final useRail = width >= 900;
    final currentPath = GoRouterState.of(context).uri.path;
    final selectedIndex = _selectedIndex(currentPath);

    if (useRail) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: selectedIndex,
              extended: width >= 1200,
              labelType: width >= 1200
                  ? NavigationRailLabelType.none
                  : NavigationRailLabelType.all,
              leading: const Padding(
                padding: EdgeInsets.only(
                  top: AppSpacing.lg,
                  bottom: AppSpacing.md,
                ),
                child: Icon(Icons.dns, color: AppColors.accent),
              ),
              destinations: [
                for (final destination in appDestinations)
                  NavigationRailDestination(
                    icon: Icon(destination.icon),
                    label: Text(destination.label),
                  ),
              ],
              onDestinationSelected: (index) =>
                  _go(context, ref, appDestinations[index]),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: child),
          ],
        ),
      );
    }

    final primary = appDestinations
        .where((item) => item.primary)
        .take(5)
        .toList();
    final primaryIndex = primary.indexWhere((item) => item.path == currentPath);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Homelab Tablet'),
        actions: [
          IconButton(
            tooltip: 'Lock privileged tabs',
            onPressed: () =>
                ref.read(appLockControllerProvider.notifier).lock(),
            icon: const Icon(Icons.lock),
          ),
        ],
      ),
      drawer: Drawer(
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              const ListTile(
                leading: Icon(Icons.dns),
                title: Text('Homelab Tablet'),
                subtitle: Text('Private server cockpit'),
              ),
              const Divider(),
              for (final destination in appDestinations)
                ListTile(
                  leading: Icon(destination.icon),
                  title: Text(destination.label),
                  selected: destination.path == currentPath,
                  trailing: destination.privileged
                      ? const Icon(Icons.lock, size: 16)
                      : null,
                  onTap: () {
                    Navigator.of(context).pop();
                    _go(context, ref, destination);
                  },
                ),
            ],
          ),
        ),
      ),
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: primaryIndex < 0 ? 0 : primaryIndex,
        destinations: [
          for (final destination in primary)
            NavigationDestination(
              icon: Icon(destination.icon),
              label: destination.label,
            ),
        ],
        onDestinationSelected: (index) => _go(context, ref, primary[index]),
      ),
    );
  }

  int _selectedIndex(String path) {
    final index = appDestinations.indexWhere((item) => item.path == path);
    return index < 0 ? 0 : index;
  }

  Future<void> _go(
    BuildContext context,
    WidgetRef ref,
    AppDestination destination,
  ) async {
    if (destination.privileged) {
      final settings = ref.read(settingsControllerProvider);
      final unlocked = await ref
          .read(appLockControllerProvider.notifier)
          .ensureUnlocked(settings);
      if (!unlocked && context.mounted) {
        context.go(destination.path);
        return;
      }
    }
    if (context.mounted) {
      context.go(destination.path);
    }
  }
}
