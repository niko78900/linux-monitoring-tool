import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/app_settings.dart';
import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/server_widget/data/server_widget_service.dart';

class HomelabTabletApp extends ConsumerStatefulWidget {
  const HomelabTabletApp({super.key, this.initialWidgetRoute});

  final String? initialWidgetRoute;

  @override
  ConsumerState<HomelabTabletApp> createState() => _HomelabTabletAppState();
}

class _HomelabTabletAppState extends ConsumerState<HomelabTabletApp> {
  StreamSubscription<String>? _widgetLaunchSubscription;
  bool _handledInitialWidgetRoute = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        ServerWidgetService.instance.syncSettings(
          ref.read(settingsControllerProvider),
        ),
      );
      _widgetLaunchSubscription = ServerWidgetService.instance
          .widgetLaunchRoutes()
          .listen(_handleWidgetRoute);
      _applyInitialWidgetRoute();
    });
  }

  @override
  void dispose() {
    _widgetLaunchSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AppSettings>(settingsControllerProvider, (_, next) {
      unawaited(ServerWidgetService.instance.syncSettings(next));
    });
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'Homelab Tablet',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      routerConfig: router,
    );
  }

  void _applyInitialWidgetRoute() {
    if (_handledInitialWidgetRoute) {
      return;
    }
    _handledInitialWidgetRoute = true;
    final route = widget.initialWidgetRoute;
    if (route != null) {
      _handleWidgetRoute(route);
    }
  }

  void _handleWidgetRoute(String route) {
    final settings = ref.read(settingsControllerProvider);
    if (!settings.onboardingComplete) {
      return;
    }
    ref.read(appRouterProvider).go(route);
  }
}
