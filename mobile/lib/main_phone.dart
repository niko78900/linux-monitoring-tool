import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/config/app_settings.dart';
import 'core/config/app_variant.dart';
import 'core/routing/phone_router.dart';
import 'features/mobile_alerts/data/mobile_alert_service.dart';
import 'features/server_widget/data/server_widget_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = await SharedPreferences.getInstance();
  String? initialWidgetRoute;

  if (Platform.isAndroid) {
    await MobileAlertService.initializeFirebaseAndRegisterBackgroundHandler();
    await ServerWidgetService.instance.bootstrap();
    initialWidgetRoute = await ServerWidgetService.instance
        .readInitialLaunchRoute(variant: AppVariant.phone);
  }

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        appVariantProvider.overrideWithValue(AppVariant.phone),
      ],
      child: HomelabApp(
        routerProvider: phoneRouterProvider,
        initialWidgetRoute: initialWidgetRoute,
      ),
    ),
  );
}
