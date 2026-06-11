import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homelab_tablet/app.dart';
import 'package:homelab_tablet/core/config/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  testWidgets('shows onboarding before setup is complete', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
        child: const HomelabTabletApp(),
      ),
    );

    expect(find.text('Homelab Tablet'), findsOneWidget);
    expect(find.text('Monitoring API'), findsOneWidget);
  });

  testWidgets('shows overview shell after onboarding', (tester) async {
    SharedPreferences.setMockInitialValues({
      'onboardingComplete': true,
      'monitoringApiUrl': '',
    });
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
        child: const HomelabTabletApp(),
      ),
    );

    await tester.pump();

    expect(find.text('Homelab Tablet'), findsWidgets);
    expect(find.byIcon(Icons.dashboard), findsWidgets);
  });
}
