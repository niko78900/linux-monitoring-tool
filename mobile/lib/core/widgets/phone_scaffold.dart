import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../security/app_lock_service.dart';

class PhoneScaffold extends ConsumerWidget {
  const PhoneScaffold({super.key, required this.child});

  final Widget child;

  static const _primaryPaths = [
    '/overview',
    '/hardware',
    '/storage',
    '/network',
    '/more',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = GoRouterState.of(context).uri.path;
    final index = _selectedIndex(path);
    return Scaffold(
      appBar: AppBar(
        title: Text(_titleFor(path)),
        actions: [
          if (path == '/wake')
            IconButton(
              tooltip: 'Lock Wake-on-LAN',
              onPressed: () =>
                  ref.read(appLockControllerProvider.notifier).lock(),
              icon: const Icon(Icons.lock),
            ),
        ],
      ),
      body: SafeArea(top: false, child: child),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard), label: 'Overview'),
          NavigationDestination(icon: Icon(Icons.memory), label: 'Hardware'),
          NavigationDestination(icon: Icon(Icons.storage), label: 'Storage'),
          NavigationDestination(icon: Icon(Icons.hub), label: 'Network'),
          NavigationDestination(icon: Icon(Icons.more_horiz), label: 'More'),
        ],
        onDestinationSelected: (next) => context.go(_primaryPaths[next]),
      ),
    );
  }

  int _selectedIndex(String path) {
    final exact = _primaryPaths.indexOf(path);
    if (exact >= 0) return exact;
    return 4;
  }

  String _titleFor(String path) => switch (path) {
    '/overview' => 'Mobile Homelab',
    '/hardware' => 'Hardware',
    '/storage' => 'Storage',
    '/network' => 'Network',
    '/gpu' => 'GPU',
    '/history' => 'History',
    '/wake' => 'Wake Main PC',
    '/settings' => 'Settings',
    _ => 'More',
  };
}
