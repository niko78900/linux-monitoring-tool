import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homelab_tablet/app.dart';
import 'package:homelab_tablet/core/config/app_settings.dart';
import 'package:homelab_tablet/core/config/app_variant.dart';
import 'package:homelab_tablet/core/routing/phone_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('phone onboarding contains metrics and Wake setup only', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          appVariantProvider.overrideWithValue(AppVariant.phone),
        ],
        child: HomelabApp(routerProvider: phoneRouterProvider),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Mobile Homelab'), findsOneWidget);
    expect(find.text('Monitoring API'), findsOneWidget);
    expect(find.text('Wake-on-LAN API'), findsOneWidget);
    expect(find.text('Wake security'), findsOneWidget);
    expect(find.textContaining('SSH'), findsNothing);
    expect(find.textContaining('SFTP'), findsNothing);
  });

  testWidgets('phone shell exposes compact allowed destinations', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({
      'onboardingComplete': true,
      'monitoringApiUrl': '',
    });
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          appVariantProvider.overrideWithValue(AppVariant.phone),
        ],
        child: HomelabApp(
          routerProvider: phoneRouterProvider,
          initialWidgetRoute: '/more',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('GPU'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
    expect(find.text('Wake Main PC'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.textContaining('Terminal'), findsNothing);
    expect(find.textContaining('Files'), findsNothing);
    expect(find.textContaining('Services'), findsNothing);
  });

  testWidgets('phone overview fits a smartphone viewport and exposes Wake', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({
      'onboardingComplete': true,
      'monitoringApiUrl': '',
    });
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          appVariantProvider.overrideWithValue(AppVariant.phone),
        ],
        child: HomelabApp(routerProvider: phoneRouterProvider),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Mobile Homelab'), findsOneWidget);
    expect(find.text('Wake Main PC'), findsOneWidget);
    expect(find.text('Overview'), findsOneWidget);
  });
}
