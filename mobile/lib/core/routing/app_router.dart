import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/actions/presentation/pages/actions_page.dart';
import '../../features/dashboard/presentation/pages/overview_page.dart';
import '../../features/files/presentation/pages/files_page.dart';
import '../../features/gpu/presentation/pages/gpu_page.dart';
import '../../features/history/presentation/pages/history_page.dart';
import '../../features/hosts/presentation/pages/host_details_page.dart';
import '../../features/hosts/presentation/pages/hosts_page.dart';
import '../../features/hardware/presentation/pages/hardware_page.dart';
import '../../features/network/presentation/pages/devices_page.dart';
import '../../features/network/presentation/pages/device_detail_page.dart';
import '../../features/network/presentation/pages/network_page.dart';
import '../../features/onboarding/presentation/onboarding_page.dart';
import '../../features/settings/presentation/pages/settings_page.dart';
import '../../features/storage/presentation/pages/storage_page.dart';
import '../../features/services/presentation/pages/services_page.dart';
import '../../features/services/presentation/pages/service_detail_page.dart';
import '../../features/terminal/presentation/pages/terminal_page.dart';
import '../config/app_settings.dart';
import '../security/app_lock_service.dart';
import '../widgets/app_scaffold.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final settings = ref.watch(settingsControllerProvider);

  return GoRouter(
    initialLocation: settings.onboardingComplete ? '/overview' : '/onboarding',
    redirect: (context, state) {
      final path = state.uri.path;
      if (!settings.onboardingComplete && path != '/onboarding') {
        return '/onboarding';
      }
      if (settings.onboardingComplete && path == '/onboarding') {
        return '/overview';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingPage(),
      ),
      ShellRoute(
        builder: (context, state, child) => AppScaffold(child: child),
        routes: [
          GoRoute(
            path: '/overview',
            builder: (context, state) => const OverviewPage(),
          ),
          GoRoute(
            path: '/hardware',
            builder: (context, state) => const HardwarePage(),
          ),
          GoRoute(
            path: '/storage',
            builder: (context, state) => const StoragePage(),
          ),
          GoRoute(path: '/gpu', builder: (context, state) => const GpuPage()),
          GoRoute(
            path: '/network',
            builder: (context, state) => const NetworkPage(),
          ),
          GoRoute(
            path: '/history',
            builder: (context, state) => const HistoryPage(),
          ),
          GoRoute(
            path: '/hosts',
            builder: (context, state) => const HostsPage(),
            routes: [
              GoRoute(
                path: ':hostId',
                builder: (context, state) => HostDetailsPage(
                  hostId: state.pathParameters['hostId'] ?? '',
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/devices',
            builder: (context, state) => const DevicesPage(),
            routes: [
              GoRoute(
                path: ':deviceId',
                builder: (context, state) => DeviceDetailPage(
                  deviceId: state.pathParameters['deviceId'] ?? '',
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/actions',
            builder: (context, state) =>
                const PrivilegedRoute(title: 'Actions', child: ActionsPage()),
          ),
          GoRoute(
            path: '/terminal',
            builder: (context, state) =>
                const PrivilegedRoute(title: 'Terminal', child: TerminalPage()),
          ),
          GoRoute(
            path: '/files',
            builder: (context, state) =>
                const PrivilegedRoute(title: 'Files', child: FilesPage()),
          ),
          GoRoute(
            path: '/services',
            builder: (context, state) => PrivilegedRoute(
              title: 'Services',
              child: ServicesPage(hostId: state.uri.queryParameters['hostId']),
            ),
          ),
          GoRoute(
            path: '/services/:serviceId',
            builder: (context, state) => PrivilegedRoute(
              title: 'Service',
              child: ServiceDetailPage(
                serviceId: state.pathParameters['serviceId'] ?? '',
              ),
            ),
          ),
          GoRoute(
            path: '/settings',
            builder: (context, state) => const SettingsPage(),
          ),
        ],
      ),
    ],
  );
});

class PrivilegedRoute extends ConsumerWidget {
  const PrivilegedRoute({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);
    final lock = ref.watch(appLockControllerProvider);
    if (!settings.requirePrivilegedUnlock || lock.isUnlocked) {
      return child;
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, size: 40),
                const SizedBox(height: 12),
                Text(title, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(
                  '$title requires biometric or device authentication.',
                  textAlign: TextAlign.center,
                ),
                if (lock.lastError != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    lock.lastError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: lock.authenticating
                      ? null
                      : () => ref
                            .read(appLockControllerProvider.notifier)
                            .ensureUnlocked(settings),
                  icon: const Icon(Icons.lock_open),
                  label: Text(lock.authenticating ? 'Unlocking...' : 'Unlock'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
