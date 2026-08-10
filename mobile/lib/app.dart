import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/config/app_settings.dart';
import 'core/config/app_variant.dart';
import 'core/security/secure_storage_service.dart';
import 'core/theme/app_theme.dart';
import 'features/mobile_alerts/data/mobile_alert_service.dart';
import 'features/server_widget/data/server_widget_service.dart';

class HomelabApp extends ConsumerStatefulWidget {
  const HomelabApp({
    super.key,
    required this.routerProvider,
    this.initialWidgetRoute,
  });

  final Provider<GoRouter> routerProvider;
  final String? initialWidgetRoute;

  @override
  ConsumerState<HomelabApp> createState() => _HomelabAppState();
}

class _HomelabAppState extends ConsumerState<HomelabApp> {
  StreamSubscription<String>? _widgetLaunchSubscription;
  StreamSubscription<String>? _notificationLaunchSubscription;
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
      final variant = ref.read(appVariantProvider);
      _widgetLaunchSubscription = ServerWidgetService.instance
          .widgetLaunchRoutes(variant: variant)
          .listen(_handleWidgetRoute);
      _notificationLaunchSubscription = MobileAlertService
          .instance
          .notificationRoutes
          .listen(_handleWidgetRoute);
      unawaited(_bootstrapMobileAlerts());
      _applyInitialWidgetRoute();
    });
  }

  @override
  void dispose() {
    _widgetLaunchSubscription?.cancel();
    _notificationLaunchSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AppSettings>(settingsControllerProvider, (_, next) {
      unawaited(ServerWidgetService.instance.syncSettings(next));
      unawaited(_configureMobileAlerts(next));
    });
    final variant = ref.watch(appVariantProvider);
    final router = ref.watch(widget.routerProvider);

    return MaterialApp.router(
      title: variant.displayName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(compact: variant.isPhone),
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
    final variant = ref.read(appVariantProvider);
    ref
        .read(widget.routerProvider)
        .go(variant.allowsRoute(route) ? route : '/overview');
  }

  Future<void> _bootstrapMobileAlerts() async {
    final settings = ref.read(settingsControllerProvider);
    await MobileAlertService.instance.bootstrap(
      settings: settings,
      preferences: ref.read(sharedPreferencesProvider),
      readMobileAlertToken: ref
          .read(secureStorageServiceProvider)
          .readMobileAlertToken,
      deviceName: ref.read(appVariantProvider).deviceLabel,
    );
  }

  Future<void> _configureMobileAlerts(AppSettings settings) {
    return MobileAlertService.instance.configure(
      settings: settings,
      preferences: ref.read(sharedPreferencesProvider),
      readMobileAlertToken: ref
          .read(secureStorageServiceProvider)
          .readMobileAlertToken,
      deviceName: ref.read(appVariantProvider).deviceLabel,
    );
  }
}
