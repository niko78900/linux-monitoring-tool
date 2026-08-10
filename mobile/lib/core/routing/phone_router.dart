import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/actions/presentation/pages/wake_page.dart';
import '../../features/dashboard/presentation/pages/overview_page.dart';
import '../../features/dashboard/presentation/pages/phone_more_page.dart';
import '../../features/gpu/presentation/pages/gpu_page.dart';
import '../../features/hardware/presentation/pages/hardware_page.dart';
import '../../features/history/presentation/pages/history_page.dart';
import '../../features/network/presentation/pages/network_page.dart';
import '../../features/onboarding/presentation/onboarding_page.dart';
import '../../features/settings/presentation/pages/settings_page.dart';
import '../../features/storage/presentation/pages/storage_page.dart';
import '../config/app_settings.dart';
import '../widgets/phone_scaffold.dart';
import 'page_transitions.dart';

final phoneRouterProvider = Provider<GoRouter>((ref) {
  final onboardingComplete = ref.watch(
    settingsControllerProvider.select(
      (settings) => settings.onboardingComplete,
    ),
  );

  return GoRouter(
    initialLocation: onboardingComplete ? '/overview' : '/onboarding',
    redirect: (context, state) {
      final path = state.uri.path;
      if (!onboardingComplete && path != '/onboarding') return '/onboarding';
      if (onboardingComplete && path == '/onboarding') return '/overview';
      if (onboardingComplete && !_phonePaths.contains(path)) {
        return '/overview';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/onboarding',
        pageBuilder: (context, state) =>
            buildFadeSlidePage(state: state, child: const OnboardingPage()),
      ),
      ShellRoute(
        builder: (context, state, child) => PhoneScaffold(child: child),
        routes: [
          _route('/overview', const OverviewPage()),
          _route('/hardware', const HardwarePage()),
          _route('/storage', const StoragePage()),
          _route('/network', const NetworkPage()),
          _route('/gpu', const GpuPage()),
          _route('/history', const HistoryPage()),
          _route('/wake', const WakePage()),
          _route('/settings', const SettingsPage()),
          _route('/more', const PhoneMorePage()),
        ],
      ),
    ],
  );
});

const _phonePaths = {
  '/onboarding',
  '/overview',
  '/hardware',
  '/storage',
  '/network',
  '/gpu',
  '/history',
  '/wake',
  '/settings',
  '/more',
};

GoRoute _route(String path, Widget child) {
  return GoRoute(
    path: path,
    pageBuilder: (context, state) =>
        buildFadeSlidePage(state: state, child: child),
  );
}
